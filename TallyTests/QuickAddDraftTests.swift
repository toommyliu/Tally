import EventKit
import XCTest
@testable import Tally

@MainActor
final class QuickAddDraftTests: XCTestCase {
    func testEventSubmissionCarriesRecurrenceThroughAllDayEditingAndEventKitMapping() throws {
        let now = Date()
        let draft = QuickAddDraft(settingsStore: makeSettings())
        draft.mode = .event
        draft.text = "Gym every monday 8-9am for 3 times #Work // Bring water"
        draft.notes = "Workout plan"

        let store = EKEventStore()
        let calendar = EKCalendar(for: .event, eventStore: store)
        guard case let .event(timedRequest) = draft.makeSubmission() else {
            return XCTFail("Expected an event submission")
        }
        let timedEvent = EKEvent(eventStore: store)
        try CalendarEventEventKitMapper.populate(timedEvent, from: timedRequest, calendar: calendar)

        XCTAssertEqual(timedEvent.title, "Gym")
        XCTAssertGreaterThan(timedEvent.startDate, now)
        XCTAssertEqual(Calendar.current.component(.weekday, from: timedEvent.startDate), 2)
        XCTAssertEqual(Calendar.current.component(.hour, from: timedEvent.startDate), 8)
        XCTAssertEqual(timedEvent.endDate.timeIntervalSince(timedEvent.startDate), 3_600)
        XCTAssertEqual(timedEvent.recurrenceRules?.first?.recurrenceEnd?.occurrenceCount, 3)
        XCTAssertEqual(timedEvent.notes, "Workout plan\nBring water")
        XCTAssertEqual(timedRequest.calendarName, "Work")

        draft.applyEventLength(.allDay)
        guard case let .event(allDayRequest) = draft.makeSubmission() else {
            return XCTFail("Expected an all-day event submission")
        }
        let allDayEvent = EKEvent(eventStore: store)
        try CalendarEventEventKitMapper.populate(allDayEvent, from: allDayRequest, calendar: calendar)

        XCTAssertTrue(allDayEvent.isAllDay)
        XCTAssertEqual(allDayEvent.title, "Gym")
        XCTAssertEqual(allDayEvent.recurrenceRules?.first?.frequency, .weekly)
        XCTAssertEqual(allDayEvent.recurrenceRules?.first?.recurrenceEnd?.occurrenceCount, 3)
        XCTAssertEqual(allDayEvent.notes, "Workout plan\nBring water")
        XCTAssertEqual(allDayRequest.calendarName, "Work")
    }

    func testDraftStartsWithConfiguredBehavior() {
        let settings = makeSettings()
        settings.quickAddBehavior = .keepOpen

        let draft = QuickAddDraft(settingsStore: settings)

        XCTAssertTrue(draft.keepsOpenAfterAdd)
    }

    func testRequestUsesStableSelectedListIdentifierAndParsedMetadata() throws {
        let settings = makeSettings()
        let draft = QuickAddDraft(settingsStore: settings)
        let work = CalendarDestinationInfo(id: "work-id", title: "Work")
        draft.text = "Call Sam 2026-08-14 3:30pm @phone P1 // Ask about renewal"
        draft.notes = "Agenda attached"
        draft.selectList(work)

        let request = try XCTUnwrap(draft.makeReminderRequest())

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

        let request = try XCTUnwrap(draft.makeReminderRequest())

        XCTAssertEqual(request.listIdentifier, "personal-id")
        XCTAssertNil(request.listName)
        XCTAssertEqual(draft.text, "Buy milk")
    }

    func testRequestIncludesRecurrenceEarlyReminderAndURL() throws {
        let settings = makeSettings()
        let draft = QuickAddDraft(settingsStore: settings)
        draft.text = "Review metrics every Monday at 9am remind 30m early https://example.com/metrics"

        let request = try XCTUnwrap(draft.makeReminderRequest())

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
        let work = CalendarDestinationInfo(id: "work-id", title: "Work")

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

    func testASaveInFlightBlocksSubmittingInEitherMode() {
        let draft = QuickAddDraft(settingsStore: makeSettings())
        draft.text = "Call Sam tomorrow"
        XCTAssertTrue(draft.canSubmit)

        draft.willSave()
        XCTAssertFalse(draft.canSubmit)
        draft.mode = .event
        XCTAssertFalse(draft.canSubmit)

        draft.reportSaveFailure("No writable calendar")
        XCTAssertTrue(draft.canSubmit)

        draft.willSave()
        draft.didSave(to: "Work")
        draft.text = "Plan launch"
        XCTAssertTrue(draft.canSubmit)
    }

    func testSwitchingToEventModeKeepsTextAndBuildsAnEvent() throws {
        let draft = QuickAddDraft(settingsStore: makeSettings())
        draft.text = "Design review 2026-10-01 2-3pm #Work @design"
        draft.notes = "Bring notes"

        draft.mode = .event
        let submission = try XCTUnwrap(draft.makeSubmission())

        guard case let .event(request) = submission else {
            return XCTFail("Expected an event submission")
        }
        XCTAssertEqual(request.title, "Design review")
        XCTAssertEqual(request.calendarName, "Work")
        XCTAssertEqual(request.tags, ["design"])
        XCTAssertEqual(request.userNotes, "Bring notes")
        XCTAssertEqual(request.timing.start.hour, 14)
        XCTAssertEqual(request.timing.end.hour, 15)
    }

    func testSwitchingModesDropsAPickedReminderList() throws {
        let draft = QuickAddDraft(settingsStore: makeSettings())
        draft.text = "Plan launch"
        draft.selectList(CalendarDestinationInfo(id: "reminders-work", title: "Work"))

        draft.mode = .event
        let request = try XCTUnwrap(draft.makeEventRequest())

        XCTAssertNil(request.calendarIdentifier)
        XCTAssertEqual(request.calendarName, "Work")
    }

    func testEventsIgnoreTheDefaultReminderList() throws {
        let settings = makeSettings()
        settings.defaultListIdentifier = "personal-id"
        let draft = QuickAddDraft(settingsStore: settings)
        draft.text = "Pay rent"
        draft.mode = .event

        let request = try XCTUnwrap(draft.makeEventRequest())

        XCTAssertNil(request.calendarIdentifier)
        XCTAssertTrue(request.timing.isAllDay)
    }

    func testPickedCalendarWinsOverASameNamedOne() throws {
        let draft = QuickAddDraft(settingsStore: makeSettings())
        draft.mode = .event
        draft.text = "Holiday party tomorrow 6pm"
        draft.selectList(CalendarDestinationInfo(id: "gmail-holidays", title: "Holidays", sourceTitle: "Gmail"))

        let request = try XCTUnwrap(draft.makeEventRequest())

        XCTAssertEqual(request.calendarIdentifier, "gmail-holidays")
        XCTAssertEqual(draft.text, "Holiday party tomorrow 6pm #Holidays")
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

extension QuickAddDraftTests {
    func testPriorityPickerPreservesSuppressedDateWithNormalizedWhitespace() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 10))!
        let draft = QuickAddDraft(settingsStore: makeSettings(), calendar: calendar, now: { now })
        draft.text = "📞 Review Oct   15 2099 P1"
        try keepToken(.date, asTextIn: draft)
        let edited = QuickAddTokenEditor.applyingPriority(9, to: draft.text, calendar: calendar,
            now: now, suppressedTokens: draft.suppressedTokens).text
        draft.applyPriority(9)
        XCTAssertEqual(draft.text, edited)
        let fields = QuickAddParser.parse(draft.text, calendar: calendar, now: now,
            suppressedTokens: draft.suppressedTokens)
        XCTAssertEqual(fields.title, "📞 Review Oct 15 2099")
        XCTAssertNil(fields.dueDate)
        XCTAssertEqual(fields.priority, 9)
        XCTAssertEqual(draft.suppressedTokens.map(\.text), ["Oct 15 2099"])
    }

    func testDatePickerPreservesSuppressedDateWithNormalizedWhitespace() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 10))!
        let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 2))!
        let draft = QuickAddDraft(settingsStore: makeSettings(), calendar: calendar, now: { now })
        draft.text = "Review Oct \t 15 2099 tomorrow"
        try keepToken(.date, asTextIn: draft)
        let selection = QuickAddDueDateSelection(date: date, includesTime: false)
        let edited = QuickAddTokenEditor.applyingDueDate(selection, to: draft.text,
            calendar: calendar, now: now, suppressedTokens: draft.suppressedTokens).text
        draft.applyDueDate(selection)
        XCTAssertEqual(draft.text, edited)
        let fields = QuickAddParser.parse(draft.text, calendar: calendar, now: now,
            suppressedTokens: draft.suppressedTokens)
        XCTAssertEqual(fields.title, "Review Oct 15 2099")
        XCTAssertEqual(fields.dueDate?.year, 2026)
        XCTAssertEqual(fields.dueDate?.month, 10)
        XCTAssertEqual(fields.dueDate?.day, 2)
        XCTAssertEqual(draft.suppressedTokens.map(\.text), ["Oct 15 2099"])
    }

    func testDatePickerPreservesSuppressedPriorityAfterWhitespaceNormalization() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 10))!
        let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 2))!
        let draft = QuickAddDraft(settingsStore: makeSettings(), calendar: calendar, now: { now })
        draft.text = "Review   P1 tomorrow"
        try keepToken(.priority, asTextIn: draft)
        draft.applyDueDate(QuickAddDueDateSelection(date: date, includesTime: false))
        let fields = QuickAddParser.parse(draft.text, calendar: calendar, now: now,
            suppressedTokens: draft.suppressedTokens)
        XCTAssertEqual(fields.title, "Review P1")
        XCTAssertEqual(fields.priority, 0)
        XCTAssertEqual(fields.dueDate?.day, 2)
        XCTAssertEqual(draft.suppressedTokens.map(\.text), ["P1"])
    }
}

extension QuickAddDraftTests {
    private var regressionCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }
    private var regressionNow: Date { regressionCalendar.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 10))! }

    func testEveryFollowedByKeptMetadataKeepsTheRemainingScheduleLiteral() {
        let cases: [(QuickAddToken.Kind, String)] = [
            (.priority, "P1"), (.list, "#Home"), (.tag, "@work"), (.url, "https://a.com")
        ]
        for (kind, text) in cases {
            for mode in [QuickAddMode.reminder, .event] {
                let input = "Call every \(text) tomorrow at 5pm"
                let fields = QuickAddParser.parse(input, mode: mode,
                    calendar: regressionCalendar, now: regressionNow,
                    suppressedTokens: [QuickAddSuppressedToken(kind: kind,
                        range: (input as NSString).range(of: text), text: text)])
                XCTAssertEqual(fields.title, input, text)
                XCTAssertNil(fields.dueDate, text)
                XCTAssertNil(fields.recurrence, text)
                if mode == .event { XCTAssertEqual(fields.eventTiming?.isAllDay, true, text) }
            }
        }
    }

    func testEveryFollowedByPunctuationWordStillParsesTheDate() {
        for word in ["!", "!!", "?", "..."] {
            let input = "Call mom every \(word) tomorrow at 5pm"
            let fields = QuickAddParser.parse(input, calendar: regressionCalendar, now: regressionNow)
            XCTAssertEqual(fields.title, "Call mom every \(word)", input)
            XCTAssertEqual(fields.dueDate?.day, 1, input)
            XCTAssertEqual(fields.dueDate?.hour, 17, input)
        }
    }

    func testTwoKeptDatesWithTheSameTextSurviveAPriorityEdit() throws {
        let draft = QuickAddDraft(settingsStore: makeSettings(), calendar: regressionCalendar, now: { self.regressionNow })
        draft.text = "Pay  Oct 15 2099  then  Oct 15 2099  P1"
        try keepToken(.date, asTextIn: draft)
        try keepToken(.date, asTextIn: draft)
        XCTAssertNil(draft.fields.dueDate)
        draft.applyPriority(9)
        let fields = draft.fields
        XCTAssertEqual(draft.text, "Pay Oct 15 2099 then Oct 15 2099 P3")
        XCTAssertNil(fields.dueDate)
        XCTAssertEqual(fields.title, "Pay Oct 15 2099 then Oct 15 2099")
        XCTAssertEqual(Set(draft.suppressedTokens.map(\.range.location)).count, 2)
    }

    func testKeptTagDoesNotMoveIntoAURLWhenClearingTheDate() throws {
        let draft = QuickAddDraft(settingsStore: makeSettings(), calendar: regressionCalendar, now: { self.regressionNow })
        draft.text = "Read https://medium.com/@work  @work  tomorrow"
        try keepToken(.tag, asTextIn: draft)
        XCTAssertEqual(draft.fields.url?.absoluteString, "https://medium.com/@work")
        XCTAssertEqual(draft.fields.tags, [])
        draft.applyDueDate(nil)
        let fields = draft.fields
        XCTAssertEqual(draft.text, "Read https://medium.com/@work @work")
        XCTAssertEqual(fields.url?.absoluteString, "https://medium.com/@work")
        XCTAssertEqual(fields.tags, [])
        XCTAssertEqual(fields.title, "Read @work")
    }

    func testKeptPriorityDoesNotMoveIntoAnotherWordWhenClearingTheDate() throws {
        let draft = QuickAddDraft(settingsStore: makeSettings(), calendar: regressionCalendar, now: { self.regressionNow })
        draft.text = "Fix AP1 bug  P1  tomorrow"
        try keepToken(.priority, asTextIn: draft)
        XCTAssertEqual(draft.fields.priority, 0)
        draft.applyDueDate(nil)
        let fields = draft.fields
        XCTAssertEqual(draft.text, "Fix AP1 bug P1")
        XCTAssertEqual(fields.priority, 0)
        XCTAssertEqual(fields.title, "Fix AP1 bug P1")
    }
}

extension QuickAddDraftTests {
    func testEveryFollowedByPunctuationStillAllowsALaterRecurrence() {
        let fields = QuickAddParser.parse("Call every ... every Monday at 9am",
            calendar: regressionCalendar, now: regressionNow)
        XCTAssertEqual(fields.title, "Call every ...")
        XCTAssertEqual(fields.dueDate?.year, 2026)
        XCTAssertEqual(fields.dueDate?.month, 10)
        XCTAssertEqual(fields.dueDate?.day, 5)
        XCTAssertEqual(fields.dueDate?.hour, 9)
        XCTAssertEqual(fields.recurrence, ReminderRecurrence(frequency: .weekly, weekdays: [.monday]))
    }

    func testEveryFollowedByPunctuationStillAllowsEventTiming() {
        let fields = QuickAddParser.parse("Standup every ! tomorrow 9am", mode: .event,
            calendar: regressionCalendar, now: regressionNow)
        XCTAssertEqual(fields.title, "Standup every !")
        XCTAssertEqual(fields.eventTiming?.isAllDay, false)
        XCTAssertEqual(fields.eventTiming?.start.year, 2026)
        XCTAssertEqual(fields.eventTiming?.start.month, 10)
        XCTAssertEqual(fields.eventTiming?.start.day, 1)
        XCTAssertEqual(fields.eventTiming?.start.hour, 9)
        XCTAssertEqual(fields.eventTiming?.end.hour, 10)
    }

    func testPriorityEditPreservesTheOriginalKeptDateAfterPrependingAnIdenticalDate() throws {
        let draft = QuickAddDraft(settingsStore: makeSettings(), calendar: regressionCalendar, now: { self.regressionNow })
        draft.text = "Review \tOct   15\t tail P1"
        try keepToken(.date, asTextIn: draft)
        draft.text = "Oct 15 2099 " + draft.text
        XCTAssertEqual(draft.fields.dueDate?.year, 2099)
        draft.applyPriority(9)
        XCTAssertEqual(draft.text, "Oct 15 2099 Review Oct 15 tail P3")
        XCTAssertEqual(draft.fields.title, "Review Oct 15 tail")
        XCTAssertEqual(draft.fields.dueDate?.year, 2099)
        XCTAssertEqual(draft.fields.priority, 9)
        XCTAssertEqual(draft.suppressedTokens.map(\.range), [NSRange(location: 19, length: 6)])
    }
}

extension QuickAddDraftTests {
    func testKeptNoteWithTrailingWhitespaceSurvivesAppendingMetadata() throws {
        let edits: [(String, String, (QuickAddDraft) -> Void)] = [
            ("priority", "P1", { $0.applyPriority(1) }),
            ("tag", "@", { $0.addTagEntry() }),
            ("list", "#Work", { $0.selectList(CalendarDestinationInfo(id: "work", title: "Work")) }),
            ("event length", "for 45m", { $0.mode = .event; $0.applyEventLength(.duration(.minutes(45))) })
        ]
        for whitespace in [" ", " \t\n", "\u{00a0}\u{2003}"] {
            for (name, token, edit) in edits {
                let draft = QuickAddDraft(settingsStore: makeSettings(), calendar: regressionCalendar,
                    now: { self.regressionNow })
                draft.text = "Buy milk tomorrow 3pm // note text" + whitespace
                try keepToken(.note, asTextIn: draft)
                edit(draft)
                XCTAssertEqual(draft.text, "Buy milk tomorrow 3pm // note text " + token, name)
                XCTAssertEqual(draft.suppressedTokens.map(\.text), ["// note text"], name)
                XCTAssertEqual(draft.fields.title, "Buy milk // note text", name)
                XCTAssertNil(draft.fields.inlineNotes, name)
                if name == "priority" { XCTAssertEqual(draft.fields.priority, 1) }
            }
        }
    }

    func testKeptNoteWithoutADateSurvivesPriorityInsertion() throws {
        let draft = QuickAddDraft(settingsStore: makeSettings(), calendar: regressionCalendar,
            now: { self.regressionNow })
        draft.text = "Review // literal "
        try keepToken(.note, asTextIn: draft)
        draft.applyPriority(9)
        XCTAssertEqual(draft.text, "Review // literal P3")
        XCTAssertEqual(draft.suppressedTokens.map(\.text), ["// literal"])
        XCTAssertEqual(draft.fields.title, "Review // literal")
        XCTAssertEqual(draft.fields.priority, 9)
        XCTAssertNil(draft.fields.inlineNotes)
    }

    func testPriorityEditOfTenThousandUnicodeNoteWordsCompletesWithinOneSecond() {
        let input = "Review P1 // " + Array(repeating: "café 🧑‍💻", count: 10_000).joined(separator: " ")
        let start = ProcessInfo.processInfo.systemUptime
        let edit = QuickAddTokenEditor.applyingPriority(9, to: input,
            calendar: regressionCalendar, now: regressionNow)
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        XCTAssertEqual(edit.text, "Review P3 // " + Array(repeating: "café 🧑‍💻", count: 10_000).joined(separator: " "))
        XCTAssertLessThan(elapsed, 1)
    }

    func testMetadataEditorsPreserveDistinctKeptDatesAcrossWhitespaceChanges() throws {
        let selection = QuickAddDueDateSelection(
            date: regressionCalendar.date(from: DateComponents(year: 2026, month: 10, day: 2))!,
            includesTime: false)
        let edits: [(String, (QuickAddDraft) -> Void)] = [
            ("pick date", { $0.applyDueDate(selection) }),
            ("clear date", { $0.applyDueDate(nil) }),
            ("event length", { $0.mode = .event; $0.applyEventLength(.duration(.minutes(30))) }),
            ("pick list", { $0.selectList(CalendarDestinationInfo(id: "work", title: "Work")) }),
            ("clear list", { $0.useDefaultList() }),
            ("pick priority", { $0.applyPriority(9) }),
            ("add tag", { $0.addTagEntry() }),
            ("edit tag", { $0.editTag(at: 0) }),
            ("remove tag", { $0.removeTag(at: 0) })
        ]
        for (name, edit) in edits {
            let draft = QuickAddDraft(settingsStore: makeSettings(), calendar: regressionCalendar,
                now: { self.regressionNow })
            draft.text = "📞 Pay  Oct 15 2099  then  Oct 15 2099  tomorrow 3pm #Home @work P1 // note"
            try keepToken(.date, asTextIn: draft)
            try keepToken(.date, asTextIn: draft)
            edit(draft)
            XCTAssertEqual(draft.suppressedTokens.map(\.text), ["Oct 15 2099", "Oct 15 2099"], name)
            XCTAssertEqual(Set(draft.suppressedTokens.map(\.range.location)).count, 2, name)
            XCTAssertTrue(draft.fields.title.contains("📞 Pay Oct 15 2099 then Oct 15 2099"), name)
            XCTAssertEqual(draft.fields.inlineNotes, "note", name)
        }
    }
}
