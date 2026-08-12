import XCTest
@testable import Tally

@MainActor
final class QuickAddDraftTests: XCTestCase {
    func testDraftStartsWithConfiguredBehavior() {
        let settings = makeSettings()
        settings.quickAddBehavior = .keepOpen

        let draft = QuickAddDraft(settingsStore: settings)

        XCTAssertTrue(draft.keepsOpenAfterAdd)
    }

    func testRequestUsesStableSelectedListIdentifierAndParsedMetadata() throws {
        let settings = makeSettings()
        let draft = QuickAddDraft(settingsStore: settings)
        let work = ReminderListInfo(id: "work-id", title: "Work")
        draft.text = "Call Sam 2026-08-14 3:30pm @phone P1 // Ask about renewal"
        draft.notes = "Agenda attached"
        draft.selectList(work)

        let request = try XCTUnwrap(draft.makeRequest())

        XCTAssertEqual(request.title, "Call Sam")
        XCTAssertEqual(request.userNotes, "Agenda attached")
        XCTAssertEqual(request.inlineNotes, "Ask about renewal")
        XCTAssertEqual(request.tags, ["phone"])
        XCTAssertEqual(request.priority, 1)
        XCTAssertEqual(request.listIdentifier, "work-id")
        XCTAssertEqual(request.listName, "Work")
    }

    func testRequestUsesConfiguredDefaultListWithoutAddingVisibleToken() throws {
        let settings = makeSettings()
        settings.defaultListIdentifier = "personal-id"
        let draft = QuickAddDraft(settingsStore: settings)
        draft.text = "Buy milk"

        let request = try XCTUnwrap(draft.makeRequest())

        XCTAssertEqual(request.listIdentifier, "personal-id")
        XCTAssertNil(request.listName)
        XCTAssertEqual(draft.text, "Buy milk")
    }

    func testRequestIncludesRecurrenceEarlyReminderAndURL() throws {
        let settings = makeSettings()
        let draft = QuickAddDraft(settingsStore: settings)
        draft.text = "Review metrics every Monday at 9am remind 30m early https://example.com/metrics"

        let request = try XCTUnwrap(draft.makeRequest())

        XCTAssertEqual(request.title, "Review metrics")
        XCTAssertEqual(
            request.recurrence,
            ReminderRecurrence(frequency: .weekly, weekdays: [.monday])
        )
        XCTAssertEqual(request.earlyReminder, ReminderEarlyReminder(amount: 30, unit: .minutes))
        XCTAssertEqual(request.url, URL(string: "https://example.com/metrics"))
    }

    func testCanKeepNaturalLanguageTokensAsTitleText() throws {
        let dateDraft = QuickAddDraft(settingsStore: makeSettings())
        dateDraft.text = "Discuss tomorrow"
        try keepToken(.date, asTextIn: dateDraft)
        XCTAssertEqual(dateDraft.fields.title, "Discuss tomorrow")
        XCTAssertNil(dateDraft.fields.dueDate)

        let recurrenceDraft = QuickAddDraft(settingsStore: makeSettings())
        recurrenceDraft.text = "Discuss every Monday until 2099-09-30"
        try keepToken(.recurrence, asTextIn: recurrenceDraft)
        XCTAssertEqual(
            recurrenceDraft.fields.title,
            "Discuss every Monday until 2099-09-30"
        )
        XCTAssertNil(recurrenceDraft.fields.recurrence)
    }

    func testKeepingDetachedTimeAsTextRemovesItsScheduleTime() throws {
        let draft = QuickAddDraft(settingsStore: makeSettings())
        draft.text = "Review tomorrow #Work at 9am"
        let originalText = draft.text as NSString
        let timeToken = try XCTUnwrap(draft.fields.usedTokens.first { token in
            token.kind == .time && originalText.substring(with: token.range) == "at 9am"
        })

        XCTAssertTrue(draft.keepTokenAsText(at: timeToken.range))

        XCTAssertEqual(draft.fields.title, "Review at 9am")
        XCTAssertEqual(draft.fields.listName, "Work")
        XCTAssertNotNil(draft.fields.dueDate)
        XCTAssertNil(draft.fields.dueDate?.hour)
        XCTAssertNil(draft.fields.dueDate?.minute)
    }

    func testCanKeepExplicitTokensAsTitleText() throws {
        let draft = QuickAddDraft(settingsStore: makeSettings())
        draft.text = "Discuss #Work @phone P1 // details"

        try keepToken(.list, asTextIn: draft)
        try keepToken(.tag, asTextIn: draft)
        try keepToken(.priority, asTextIn: draft)
        try keepToken(.note, asTextIn: draft)

        XCTAssertEqual(draft.fields.title, "Discuss #Work @phone P1 // details")
        XCTAssertNil(draft.fields.listName)
        XCTAssertEqual(draft.fields.tags, [])
        XCTAssertEqual(draft.fields.priority, 0)
        XCTAssertNil(draft.fields.inlineNotes)
        XCTAssertTrue(draft.fields.usedTokens.isEmpty)
    }

    func testKeptTokenTracksEditsOutsideItAndReactivatesWhenEdited() throws {
        let draft = QuickAddDraft(settingsStore: makeSettings())
        draft.text = "Review every Monday"
        try keepToken(.recurrence, asTextIn: draft)

        draft.text = "Please Review every Monday"

        XCTAssertEqual(draft.fields.title, "Please Review every Monday")
        XCTAssertNil(draft.fields.recurrence)

        draft.text = "Please Review every Tuesday"

        XCTAssertEqual(draft.fields.title, "Please Review")
        XCTAssertEqual(
            draft.fields.recurrence,
            ReminderRecurrence(frequency: .weekly, weekdays: [.tuesday])
        )
    }

    func testCanKeepEarlyReminderAndURLTokensAsTitleText() throws {
        let draft = QuickAddDraft(settingsStore: makeSettings())
        draft.text = "Review tomorrow at 9am remind 30m early https://example.com/review"

        try keepToken(.earlyReminder, asTextIn: draft)
        try keepToken(.url, asTextIn: draft)

        XCTAssertEqual(
            draft.fields.title,
            "Review remind 30m early https://example.com/review"
        )
        XCTAssertNil(draft.fields.earlyReminder)
        XCTAssertNil(draft.fields.url)
    }

    func testSuppressedMetadataAllowsReplacementOfSameKind() throws {
        let recurrenceDraft = QuickAddDraft(settingsStore: makeSettings())
        recurrenceDraft.text = "Review every Monday"
        try keepToken(.recurrence, asTextIn: recurrenceDraft)
        recurrenceDraft.text += " every Tuesday"

        XCTAssertEqual(recurrenceDraft.fields.title, "Review every Monday")
        XCTAssertEqual(
            recurrenceDraft.fields.recurrence,
            ReminderRecurrence(frequency: .weekly, weekdays: [.tuesday])
        )

        let urlDraft = QuickAddDraft(settingsStore: makeSettings())
        urlDraft.text = "Read https://one.example"
        try keepToken(.url, asTextIn: urlDraft)
        urlDraft.text += " https://two.example"

        XCTAssertEqual(urlDraft.fields.title, "Read https://one.example")
        XCTAssertEqual(urlDraft.fields.url, URL(string: "https://two.example"))

        let earlyReminderDraft = QuickAddDraft(settingsStore: makeSettings())
        earlyReminderDraft.text = "Review tomorrow at 2pm remind 30m early"
        try keepToken(.earlyReminder, asTextIn: earlyReminderDraft)
        earlyReminderDraft.text += " remind 2h before"

        XCTAssertEqual(earlyReminderDraft.fields.title, "Review remind 30m early")
        XCTAssertEqual(
            earlyReminderDraft.fields.earlyReminder,
            ReminderEarlyReminder(amount: 2, unit: .hours)
        )
    }

    func testEditingSuppressedTokenAtEndBoundaryReactivatesNLP() throws {
        let draft = QuickAddDraft(settingsStore: makeSettings())
        draft.text = "Open https://example.com"
        let token = try XCTUnwrap(draft.fields.usedTokens.first { $0.kind == .url })

        XCTAssertTrue(draft.keepTokenAsText(at: token.range))
        XCTAssertNil(draft.fields.url)

        draft.text += "/report"

        XCTAssertEqual(draft.fields.title, "Open")
        XCTAssertEqual(draft.fields.url, URL(string: "https://example.com/report"))
        XCTAssertTrue(draft.suppressedTokens.isEmpty)
    }

    func testSentencePunctuationKeepsSuppressedURLLiteral() throws {
        let draft = QuickAddDraft(settingsStore: makeSettings())
        draft.text = "Open https://example.com"
        let token = try XCTUnwrap(draft.fields.usedTokens.first { $0.kind == .url })

        XCTAssertTrue(draft.keepTokenAsText(at: token.range))
        draft.text += "."

        XCTAssertEqual(draft.fields.title, "Open https://example.com.")
        XCTAssertNil(draft.fields.url)
        XCTAssertEqual(draft.suppressedTokens.count, 1)
    }

    func testEditingPastSentencePunctuationReactivatesSuppressedURL() throws {
        let draft = QuickAddDraft(settingsStore: makeSettings())
        draft.text = "Open https://example.com"
        let token = try XCTUnwrap(draft.fields.usedTokens.first { $0.kind == .url })

        XCTAssertTrue(draft.keepTokenAsText(at: token.range))
        draft.text += "."
        draft.text += "au"

        XCTAssertEqual(draft.fields.title, "Open")
        XCTAssertEqual(draft.fields.url, URL(string: "https://example.com.au"))
        XCTAssertTrue(draft.suppressedTokens.isEmpty)
    }

    func testDueDatePickerPreservesUnrelatedSuppressedMetadata() throws {
        let calendar = Calendar(identifier: .gregorian)
        let selectionDate = try XCTUnwrap(calendar.date(from: DateComponents(
            calendar: calendar,
            year: 2026,
            month: 8,
            day: 14,
            hour: 15,
            minute: 0
        )))
        let selection = QuickAddDueDateSelection(date: selectionDate, includesTime: true)

        let urlDraft = QuickAddDraft(settingsStore: makeSettings())
        urlDraft.text = "Review every Monday at 9am https://example.com until Sep 30"
        try keepToken(.url, asTextIn: urlDraft)
        urlDraft.applyDueDate(selection)

        XCTAssertNil(urlDraft.fields.url)
        XCTAssertEqual(urlDraft.suppressedTokens.map(\.kind), [.url])
        XCTAssertTrue(urlDraft.fields.title.contains("https://example.com"))

        let earlyDraft = QuickAddDraft(settingsStore: makeSettings())
        earlyDraft.text = "Review every Monday at 9am remind 30m early until Sep 30"
        try keepToken(.earlyReminder, asTextIn: earlyDraft)
        earlyDraft.applyDueDate(selection)

        XCTAssertNil(earlyDraft.fields.earlyReminder)
        XCTAssertEqual(earlyDraft.suppressedTokens.map(\.kind), [.earlyReminder])
        XCTAssertTrue(earlyDraft.fields.title.contains("remind 30m early"))
    }

    func testMetadataPickersPreserveSuppressedURLAcrossDuplicateTokens() throws {
        let work = ReminderListInfo(id: "work-id", title: "Work")

        let listDraft = QuickAddDraft(settingsStore: makeSettings())
        listDraft.text = "Review #One https://example.com #Two tomorrow"
        try keepToken(.url, asTextIn: listDraft)
        listDraft.selectList(work)

        XCTAssertEqual(listDraft.text, "Review #Work https://example.com tomorrow")
        XCTAssertNil(listDraft.fields.url)
        XCTAssertEqual(listDraft.fields.listName, "Work")
        XCTAssertEqual(listDraft.suppressedTokens.map(\.kind), [.url])

        let defaultListDraft = QuickAddDraft(settingsStore: makeSettings())
        defaultListDraft.text = "Review #One https://example.com #Two tomorrow"
        try keepToken(.url, asTextIn: defaultListDraft)
        defaultListDraft.useDefaultList()

        XCTAssertEqual(defaultListDraft.text, "Review https://example.com tomorrow")
        XCTAssertNil(defaultListDraft.fields.url)
        XCTAssertNil(defaultListDraft.fields.listName)
        XCTAssertEqual(defaultListDraft.suppressedTokens.map(\.kind), [.url])

        let priorityDraft = QuickAddDraft(settingsStore: makeSettings())
        priorityDraft.text = "Review P1 https://example.com P2 tomorrow"
        try keepToken(.url, asTextIn: priorityDraft)
        priorityDraft.applyPriority(9)

        XCTAssertEqual(priorityDraft.text, "Review P3 https://example.com tomorrow")
        XCTAssertNil(priorityDraft.fields.url)
        XCTAssertEqual(priorityDraft.fields.priority, 9)
        XCTAssertEqual(priorityDraft.suppressedTokens.map(\.kind), [.url])
    }

    func testDueDatePickerReanchorsAnIdenticalSuppressedDate() throws {
        let calendar = Calendar(identifier: .gregorian)
        let selectionDate = try XCTUnwrap(calendar.date(from: DateComponents(
            calendar: calendar,
            year: 2099,
            month: 8,
            day: 14,
            hour: 8,
            minute: 0
        )))
        let draft = QuickAddDraft(settingsStore: makeSettings())
        draft.text = "Review 2099-08-14"
        try keepToken(.date, asTextIn: draft)
        draft.text = "Review every Monday 2099-08-14"

        draft.applyDueDate(QuickAddDueDateSelection(date: selectionDate, includesTime: true))

        XCTAssertEqual(draft.text, "Review 2099-08-14 8:00am 2099-08-14")
        XCTAssertEqual(draft.fields.title, "Review 2099-08-14")
        XCTAssertEqual(draft.fields.dueDate?.year, 2099)
        XCTAssertEqual(draft.fields.dueDate?.month, 8)
        XCTAssertEqual(draft.fields.dueDate?.day, 14)
        XCTAssertEqual(draft.fields.dueDate?.hour, 8)
        XCTAssertEqual(draft.suppressedTokens.map(\.range.location), [
            (draft.text as NSString).range(of: "2099-08-14", options: .backwards).location
        ])
    }

    func testSaveFailurePreservesDraftAndSuccessfulSaveResetsIt() {
        let settings = makeSettings()
        let draft = QuickAddDraft(settingsStore: settings)
        draft.text = "Call Sam tomorrow"
        draft.notes = "Bring the agenda"

        draft.reportSaveFailure("No writable list")

        XCTAssertEqual(draft.text, "Call Sam tomorrow")
        XCTAssertEqual(draft.notes, "Bring the agenda")
        XCTAssertEqual(draft.errorMessage, "No writable list")

        draft.didSave(to: "Work")

        XCTAssertEqual(draft.text, "")
        XCTAssertEqual(draft.notes, "")
        XCTAssertNil(draft.errorMessage)
        XCTAssertEqual(draft.confirmationMessage, "Added to Work")
    }

    private func makeSettings() -> AppSettingsStore {
        let suiteName = "TallyTests.QuickAddDraft.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        return AppSettingsStore(userDefaults: userDefaults)
    }

    private func keepToken(
        _ kind: QuickAddToken.Kind,
        asTextIn draft: QuickAddDraft,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let token = try XCTUnwrap(
            draft.fields.usedTokens.first(where: { $0.kind == kind }),
            "Missing \(kind) token",
            file: file,
            line: line
        )
        XCTAssertTrue(
            draft.keepTokenAsText(at: NSRange(location: token.range.location, length: 0)),
            file: file,
            line: line
        )
    }
}
