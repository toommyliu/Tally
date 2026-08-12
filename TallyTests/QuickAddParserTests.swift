import XCTest
@testable import Tally

final class QuickAddParserTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    func testParsesTodoistStyleMetadata() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 13)))

        let fields = QuickAddParser.parse(
            "This is my test entry #Testing Today @mac P1",
            calendar: calendar,
            now: now
        )

        XCTAssertEqual(fields.title, "This is my test entry")
        XCTAssertEqual(fields.listName, "Testing")
        XCTAssertEqual(fields.tags, ["mac"])
        XCTAssertEqual(fields.priority, 1)
        XCTAssertEqual(fields.dueDate?.year, 2026)
        XCTAssertEqual(fields.dueDate?.month, 5)
        XCTAssertEqual(fields.dueDate?.day, 13)
        XCTAssertEqual(fields.usedTokens.count, 4)
    }

    func testParsesEncodedListTokenWithoutLosingUnderscores() throws {
        let encodedSpace = QuickAddParser.parse("File report #Work%20Items", calendar: calendar)
        XCTAssertEqual(encodedSpace.listName, "Work Items")

        let literalUnderscore = QuickAddParser.parse("File report #Work_Items", calendar: calendar)
        XCTAssertEqual(literalUnderscore.listName, "Work_Items")

        let literalPercentEncoding = QuickAddParser.parse("File report #Work%2520Items", calendar: calendar)
        XCTAssertEqual(literalPercentEncoding.listName, "Work%20Items")
    }

    func testTomorrowAliasUsesNextDay() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 12, day: 31)))

        let fields = QuickAddParser.parse("Renew license tmr p2", calendar: calendar, now: now)

        XCTAssertEqual(fields.title, "Renew license")
        XCTAssertEqual(fields.priority, 5)
        XCTAssertEqual(fields.dueDate?.year, 2027)
        XCTAssertEqual(fields.dueDate?.month, 1)
        XCTAssertEqual(fields.dueDate?.day, 1)
    }

    func testParsesDatePickerToken() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 13)))
        let input = "Renew license 2026-06-04"

        let fields = QuickAddParser.parse(input, calendar: calendar, now: now)

        XCTAssertEqual(fields.title, "Renew license")
        XCTAssertDate(fields.dueDate, year: 2026, month: 6, day: 4, hour: nil, minute: nil)
        XCTAssertToken(in: fields, originalText: input, kind: .date, equals: "2026-06-04")
    }

    func testParsesDatePickerTokenWithTime() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 13)))
        let input = "Renew license 2026-08-14 3:30pm"

        let fields = QuickAddParser.parse(input, calendar: calendar, now: now)

        XCTAssertEqual(fields.title, "Renew license")
        XCTAssertDate(fields.dueDate, year: 2026, month: 8, day: 14, hour: 15, minute: 30)
        XCTAssertToken(in: fields, originalText: input, kind: .time, equals: "2026-08-14 3:30pm")
    }

    func testDueDateTokenEditorInsertsDateOnlyToken() throws {
        let date = try date(year: 2026, month: 8, day: 14, hour: 15, minute: 30)
        let selection = QuickAddDueDateSelection(date: date, includesTime: false)

        let output = QuickAddDueDateTokenEditor.applying(selection, to: "Renew license", calendar: calendar)

        XCTAssertEqual(output, "Renew license 2026-08-14")
    }

    func testDueDateTokenEditorInsertsDateAndTimeToken() throws {
        let date = try date(year: 2026, month: 8, day: 14, hour: 15, minute: 30)
        let selection = QuickAddDueDateSelection(date: date, includesTime: true)

        let output = QuickAddDueDateTokenEditor.applying(selection, to: "Renew license", calendar: calendar)

        XCTAssertEqual(output, "Renew license 2026-08-14 3:30pm")
    }

    func testDueDateTokenEditorReplacesDateOnlyToken() throws {
        let date = try date(year: 2026, month: 8, day: 14, hour: 15, minute: 30)
        let selection = QuickAddDueDateSelection(date: date, includesTime: false)

        let output = QuickAddDueDateTokenEditor.applying(
            selection,
            to: "Renew license 2026-06-04 #Work P2",
            calendar: calendar
        )

        XCTAssertEqual(output, "Renew license 2026-08-14 #Work P2")
    }

    func testDueDateTokenEditorReplacesDateAndTimeToken() throws {
        let now = try date(year: 2026, month: 5, day: 13, hour: 9, minute: 15)
        let date = try date(year: 2026, month: 8, day: 14, hour: 15, minute: 30)
        let selection = QuickAddDueDateSelection(date: date, includesTime: true)

        let output = QuickAddDueDateTokenEditor.applying(
            selection,
            to: "Call Sam today at 3:30pm #Work",
            calendar: calendar,
            now: now
        )

        XCTAssertEqual(output, "Call Sam 2026-08-14 3:30pm #Work")
    }

    func testDueDateTokenEditorReplacesRelativeTimeTokens() throws {
        let now = try date(year: 2026, month: 5, day: 13, hour: 9, minute: 15)
        let date = try date(year: 2026, month: 8, day: 14, hour: 15, minute: 30)
        let selection = QuickAddDueDateSelection(date: date, includesTime: true)

        let laterToday = QuickAddDueDateTokenEditor.applying(
            selection,
            to: "Review notes later today P2",
            calendar: calendar,
            now: now
        )
        let relativeHours = QuickAddDueDateTokenEditor.applying(
            selection,
            to: "Submit report in 2 hours P1",
            calendar: calendar,
            now: now
        )

        XCTAssertEqual(laterToday, "Review notes 2026-08-14 3:30pm P2")
        XCTAssertEqual(relativeHours, "Submit report 2026-08-14 3:30pm P1")
    }

    func testDueDateTokenEditorClearsDueDateTokens() throws {
        let now = try date(year: 2026, month: 5, day: 13, hour: 9, minute: 15)

        let dateAndTime = QuickAddDueDateTokenEditor.applying(
            nil,
            to: "Call Sam today at 3:30pm #Work @phone P1",
            calendar: calendar,
            now: now
        )
        let relativeTime = QuickAddDueDateTokenEditor.applying(
            nil,
            to: "Review notes later today #Work P2",
            calendar: calendar,
            now: now
        )

        XCTAssertEqual(dateAndTime, "Call Sam #Work @phone P1")
        XCTAssertEqual(relativeTime, "Review notes #Work P2")
    }

    func testDueDateTokenEditorRespectsSuppressedTokens() throws {
        let now = try date(year: 2026, month: 5, day: 13, hour: 9, minute: 15)
        let input = "Dinner 6pm"
        let parsed = QuickAddParser.parse(input, calendar: calendar, now: now)
        let token = try XCTUnwrap(parsed.usedTokens.first)
        let date = try date(year: 2026, month: 8, day: 14, hour: 15, minute: 30)
        let selection = QuickAddDueDateSelection(date: date, includesTime: false)

        let output = QuickAddDueDateTokenEditor.applying(
            selection,
            to: input,
            calendar: calendar,
            now: now,
            suppressedTokens: [
                QuickAddSuppressedToken(
                    kind: token.kind,
                    range: token.range,
                    text: (input as NSString).substring(with: token.range)
                )
            ]
        )

        XCTAssertEqual(output, "Dinner 6pm 2026-08-14")
    }

    func testPendingTagMarkerDoesNotBecomeTitleText() {
        let emptyMarker = QuickAddParser.parse("@", calendar: calendar)
        XCTAssertEqual(emptyMarker.title, "")
        XCTAssertEqual(emptyMarker.tags, [])
        XCTAssertEqual(emptyMarker.usedTokens.count, 1)
        XCTAssertEqual(emptyMarker.usedTokens.first?.kind, .tag)

        let trailingMarker = QuickAddParser.parse("Call Sam @phone @", calendar: calendar)
        XCTAssertEqual(trailingMarker.title, "Call Sam")
        XCTAssertEqual(trailingMarker.tags, ["phone"])
    }

    func testTagTokenEditorReusesPendingMarker() {
        let firstEdit = QuickAddTokenEditor.beginningTagEntry(in: "Call Sam", calendar: calendar)
        XCTAssertEqual(firstEdit.text, "Call Sam @")
        XCTAssertEqual(firstEdit.selectedRange?.location, ("Call Sam @" as NSString).length)
        XCTAssertEqual(firstEdit.selectedRange?.length, 0)

        let repeatedEdit = QuickAddTokenEditor.beginningTagEntry(in: firstEdit.text, calendar: calendar)
        XCTAssertEqual(repeatedEdit.text, "Call Sam @")
        XCTAssertEqual(repeatedEdit.selectedRange?.location, ("Call Sam @" as NSString).length)
        XCTAssertEqual(repeatedEdit.selectedRange?.length, 0)

        let collapsedEdit = QuickAddTokenEditor.beginningTagEntry(in: "Call Sam @ @", calendar: calendar)
        XCTAssertEqual(collapsedEdit.text, "Call Sam @")
        XCTAssertEqual(collapsedEdit.selectedRange?.location, ("Call Sam @" as NSString).length)
        XCTAssertEqual(collapsedEdit.selectedRange?.length, 0)
    }

    func testTagTokenEditorAddsAnotherTagEntryWhenRequested() {
        let edit = QuickAddTokenEditor.addingTagEntry(in: "Call Sam @phone", calendar: calendar)

        XCTAssertEqual(edit.text, "Call Sam @phone @")
        XCTAssertEqual(edit.selectedRange?.location, ("Call Sam @phone @" as NSString).length)
        XCTAssertEqual(edit.selectedRange?.length, 0)
    }

    func testTagTokenEditorReusesExistingTagInsteadOfAddingAnotherMarker() {
        let edit = QuickAddTokenEditor.beginningTagEntry(in: "Call Sam @phone", calendar: calendar)

        XCTAssertEqual(edit.text, "Call Sam @phone")
        XCTAssertEqual(edit.selectedRange?.location, 10)
        XCTAssertEqual(edit.selectedRange?.length, 5)
    }

    func testTagTokenEditorReusesLastExistingTag() {
        let edit = QuickAddTokenEditor.beginningTagEntry(in: "Call Sam @phone @work", calendar: calendar)

        XCTAssertEqual(edit.text, "Call Sam @phone @work")
        XCTAssertEqual(edit.selectedRange?.location, 17)
        XCTAssertEqual(edit.selectedRange?.length, 4)
    }

    func testTagTokenEditorEditsSpecificTag() {
        let firstTag = QuickAddTokenEditor.editingTag(at: 0, in: "Call Sam @phone @work", calendar: calendar)
        let secondTag = QuickAddTokenEditor.editingTag(at: 1, in: "Call Sam @phone @work", calendar: calendar)

        XCTAssertEqual(firstTag.text, "Call Sam @phone @work")
        XCTAssertEqual(firstTag.selectedRange?.location, 10)
        XCTAssertEqual(firstTag.selectedRange?.length, 5)
        XCTAssertEqual(secondTag.text, "Call Sam @phone @work")
        XCTAssertEqual(secondTag.selectedRange?.location, 17)
        XCTAssertEqual(secondTag.selectedRange?.length, 4)
    }

    func testTagTokenEditorRemovesSpecificTag() {
        let firstRemoved = QuickAddTokenEditor.removingTag(at: 0, from: "Call Sam @phone @work", calendar: calendar)
        let secondRemoved = QuickAddTokenEditor.removingTag(at: 1, from: "Call Sam @phone @work", calendar: calendar)

        XCTAssertEqual(firstRemoved, "Call Sam @work")
        XCTAssertEqual(secondRemoved, "Call Sam @phone")
    }

    func testListTokenEditorReplacesExistingListTokens() {
        let single = QuickAddTokenEditor.applyingList("Deep Work", to: "Call Sam #Home P1", calendar: calendar)
        let multiple = QuickAddTokenEditor.applyingList("Errands", to: "Call Sam #Home #Work P1", calendar: calendar)

        XCTAssertEqual(single, "Call Sam #Deep%20Work P1")
        XCTAssertEqual(multiple, "Call Sam #Errands P1")
    }

    func testMetadataEditorsInsertTokensBeforeInlineNotes() {
        let input = "Call Sam // Ask about renewal"
        let withList = QuickAddTokenEditor.applyingList("Work", to: input, calendar: calendar)
        let withPriority = QuickAddTokenEditor.applyingPriority(1, to: input, calendar: calendar)
        let withTag = QuickAddTokenEditor.addingTagEntry(in: input, calendar: calendar)

        XCTAssertEqual(withList, "Call Sam #Work // Ask about renewal")
        XCTAssertEqual(withPriority, "Call Sam P1 // Ask about renewal")
        XCTAssertEqual(withTag.text, "Call Sam @ // Ask about renewal")
        XCTAssertEqual(withTag.selectedRange, NSRange(location: 10, length: 0))
    }

    func testPriorityTokenEditorReplacesAndClearsExistingPriorityTokens() {
        let inserted = QuickAddTokenEditor.applyingPriority(1, to: "Call Sam #Work", calendar: calendar)
        let replaced = QuickAddTokenEditor.applyingPriority(5, to: "Call Sam P1 #Work", calendar: calendar)
        let cleared = QuickAddTokenEditor.applyingPriority(0, to: "Call Sam P1 P2 #Work", calendar: calendar)

        XCTAssertEqual(inserted, "Call Sam #Work P1")
        XCTAssertEqual(replaced, "Call Sam P2 #Work")
        XCTAssertEqual(cleared, "Call Sam #Work")
    }

    func testParsesDueTimeAfterDateToken() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 13)))

        let fields = QuickAddParser.parse("Call Sam today at 3:30pm #Work", calendar: calendar, now: now)

        XCTAssertEqual(fields.title, "Call Sam")
        XCTAssertEqual(fields.listName, "Work")
        XCTAssertEqual(fields.dueDate?.year, 2026)
        XCTAssertEqual(fields.dueDate?.month, 5)
        XCTAssertEqual(fields.dueDate?.day, 13)
        XCTAssertEqual(fields.dueDate?.hour, 15)
        XCTAssertEqual(fields.dueDate?.minute, 30)
        let timeToken = try XCTUnwrap(fields.usedTokens.first { $0.kind == .time })
        let originalText = "Call Sam today at 3:30pm #Work" as NSString
        XCTAssertEqual(originalText.substring(with: timeToken.range), "today at 3:30pm")
    }

    func testParsesRelativeMinutes() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 13, hour: 9, minute: 15)))
        let input = "Check oven in 45 minutes"

        let fields = QuickAddParser.parse(input, calendar: calendar, now: now)

        XCTAssertEqual(fields.title, "Check oven")
        XCTAssertDate(fields.dueDate, year: 2026, month: 5, day: 13, hour: 10, minute: 0)
        XCTAssertToken(in: fields, originalText: input, kind: .time, equals: "in 45 minutes")
    }

    func testParsesRelativeHoursAcrossDayBoundary() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 13, hour: 23, minute: 30)))
        let input = "Submit report in 2 hours P1"

        let fields = QuickAddParser.parse(input, calendar: calendar, now: now)

        XCTAssertEqual(fields.title, "Submit report")
        XCTAssertEqual(fields.priority, 1)
        XCTAssertDate(fields.dueDate, year: 2026, month: 5, day: 14, hour: 1, minute: 30)
        XCTAssertToken(in: fields, originalText: input, kind: .time, equals: "in 2 hours")
    }

    func testParsesRelativeDays() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 13, hour: 9, minute: 15)))
        let input = "Follow up in 3 days"

        let fields = QuickAddParser.parse(input, calendar: calendar, now: now)

        XCTAssertEqual(fields.title, "Follow up")
        XCTAssertDate(fields.dueDate, year: 2026, month: 5, day: 16, hour: nil, minute: nil)
        XCTAssertToken(in: fields, originalText: input, kind: .date, equals: "in 3 days")
    }

    func testParsesNextWeek() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 13, hour: 9, minute: 15)))
        let input = "Plan roadmap next week"

        let fields = QuickAddParser.parse(input, calendar: calendar, now: now)

        XCTAssertEqual(fields.title, "Plan roadmap")
        XCTAssertDate(fields.dueDate, year: 2026, month: 5, day: 20, hour: nil, minute: nil)
        XCTAssertToken(in: fields, originalText: input, kind: .date, equals: "next week")
    }

    func testParsesTonight() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 13, hour: 9, minute: 15)))
        let input = "Take out trash tonight"

        let fields = QuickAddParser.parse(input, calendar: calendar, now: now)

        XCTAssertEqual(fields.title, "Take out trash")
        XCTAssertDate(fields.dueDate, year: 2026, month: 5, day: 13, hour: 18, minute: 0)
        XCTAssertToken(in: fields, originalText: input, kind: .time, equals: "tonight")
    }

    func testParsesThisAfternoon() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 13, hour: 9, minute: 15)))
        let input = "Call dentist this afternoon @phone"

        let fields = QuickAddParser.parse(input, calendar: calendar, now: now)

        XCTAssertEqual(fields.title, "Call dentist")
        XCTAssertEqual(fields.tags, ["phone"])
        XCTAssertDate(fields.dueDate, year: 2026, month: 5, day: 13, hour: 14, minute: 0)
        XCTAssertToken(in: fields, originalText: input, kind: .time, equals: "this afternoon")
    }

    func testParsesCompactRelativeDuration() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 13, hour: 9, minute: 15)))
        let input = "Stretch in 90m"

        let fields = QuickAddParser.parse(input, calendar: calendar, now: now)

        XCTAssertEqual(fields.title, "Stretch")
        XCTAssertDate(fields.dueDate, year: 2026, month: 5, day: 13, hour: 10, minute: 45)
        XCTAssertToken(in: fields, originalText: input, kind: .time, equals: "in 90m")
    }

    func testParsesArticleRelativeDuration() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 13, hour: 9, minute: 15)))
        let input = "Start laundry in an hour"

        let fields = QuickAddParser.parse(input, calendar: calendar, now: now)

        XCTAssertEqual(fields.title, "Start laundry")
        XCTAssertDate(fields.dueDate, year: 2026, month: 5, day: 13, hour: 10, minute: 15)
        XCTAssertToken(in: fields, originalText: input, kind: .time, equals: "in an hour")
    }

    func testParsesSpelledRelativeDuration() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 13, hour: 9, minute: 15)))
        let input = "Follow up in three days"

        let fields = QuickAddParser.parse(input, calendar: calendar, now: now)

        XCTAssertEqual(fields.title, "Follow up")
        XCTAssertDate(fields.dueDate, year: 2026, month: 5, day: 16, hour: nil, minute: nil)
        XCTAssertToken(in: fields, originalText: input, kind: .date, equals: "in three days")
    }

    func testParsesCompoundSpelledRelativeDuration() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 13, hour: 9, minute: 15)))

        let spaced = QuickAddParser.parse("Submit form in twenty one days", calendar: calendar, now: now)
        XCTAssertEqual(spaced.title, "Submit form")
        XCTAssertDate(spaced.dueDate, year: 2026, month: 6, day: 3, hour: nil, minute: nil)

        let hyphenated = QuickAddParser.parse("Submit form in twenty-one days", calendar: calendar, now: now)
        XCTAssertEqual(hyphenated.title, "Submit form")
        XCTAssertDate(hyphenated.dueDate, year: 2026, month: 6, day: 3, hour: nil, minute: nil)
    }

    func testParsesFuzzyRelativeDurationAmounts() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 13, hour: 9, minute: 15)))

        let couple = QuickAddParser.parse("Check back in a couple of days", calendar: calendar, now: now)
        XCTAssertEqual(couple.title, "Check back")
        XCTAssertDate(couple.dueDate, year: 2026, month: 5, day: 15, hour: nil, minute: nil)

        let few = QuickAddParser.parse("Check back in a few hours", calendar: calendar, now: now)
        XCTAssertEqual(few.title, "Check back")
        XCTAssertDate(few.dueDate, year: 2026, month: 5, day: 13, hour: 12, minute: 15)
    }

    func testParsesHalfRelativeDurations() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 13, hour: 9, minute: 15)))

        let halfHour = QuickAddParser.parse("Move laundry in half an hour", calendar: calendar, now: now)
        XCTAssertEqual(halfHour.title, "Move laundry")
        XCTAssertDate(halfHour.dueDate, year: 2026, month: 5, day: 13, hour: 9, minute: 45)

        let halfDay = QuickAddParser.parse("Check process in half a day", calendar: calendar, now: now)
        XCTAssertEqual(halfDay.title, "Check process")
        XCTAssertDate(halfDay.dueDate, year: 2026, month: 5, day: 13, hour: 21, minute: 15)
    }

    func testParsesBareRelativeDuration() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 13, hour: 9, minute: 15)))
        let input = "Check upload 2h"

        let fields = QuickAddParser.parse(input, calendar: calendar, now: now)

        XCTAssertEqual(fields.title, "Check upload")
        XCTAssertDate(fields.dueDate, year: 2026, month: 5, day: 13, hour: 11, minute: 15)
        XCTAssertToken(in: fields, originalText: input, kind: .time, equals: "2h")
    }

    func testParsesLaterToday() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 13, hour: 9, minute: 15)))
        let input = "Review notes later today"

        let fields = QuickAddParser.parse(input, calendar: calendar, now: now)

        XCTAssertEqual(fields.title, "Review notes")
        XCTAssertDate(fields.dueDate, year: 2026, month: 5, day: 13, hour: 17, minute: 0)
        XCTAssertToken(in: fields, originalText: input, kind: .time, equals: "later today")
    }

    func testNamedDaypartsAlwaysResolveInTheFuture() throws {
        let now = try date(year: 2026, month: 5, day: 13, hour: 20, minute: 0)
        let expectations: [(String, Int)] = [
            ("Take out trash tonight", 18),
            ("Review notes later today", 17),
            ("Call dentist this afternoon", 14)
        ]

        for (input, expectedHour) in expectations {
            let fields = QuickAddParser.parse(input, calendar: calendar, now: now)

            XCTAssertDate(
                fields.dueDate,
                year: 2026,
                month: 5,
                day: 14,
                hour: expectedHour,
                minute: 0
            )
        }
    }

    func testParsesNextWeekday() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 13, hour: 9, minute: 15)))
        let input = "Book flight next monday"

        let fields = QuickAddParser.parse(input, calendar: calendar, now: now)

        XCTAssertEqual(fields.title, "Book flight")
        XCTAssertDate(fields.dueDate, year: 2026, month: 5, day: 18, hour: nil, minute: nil)
        XCTAssertToken(in: fields, originalText: input, kind: .date, equals: "next monday")
    }

    func testParsesTodoistStyleDateAliasesAndTime() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 13, hour: 9, minute: 15)))
        let input = "Pay rent tom 9am"

        let fields = QuickAddParser.parse(input, calendar: calendar, now: now)

        XCTAssertEqual(fields.title, "Pay rent")
        XCTAssertDate(fields.dueDate, year: 2026, month: 5, day: 14, hour: 9, minute: 0)
        XCTAssertToken(in: fields, originalText: input, kind: .time, equals: "tom 9am")
    }

    func testParsesBareWeekdayWithTime() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 13, hour: 9, minute: 15)))
        let input = "Ship deck fri at 7pm"

        let fields = QuickAddParser.parse(input, calendar: calendar, now: now)

        XCTAssertEqual(fields.title, "Ship deck")
        XCTAssertDate(fields.dueDate, year: 2026, month: 5, day: 15, hour: 19, minute: 0)
        XCTAssertToken(in: fields, originalText: input, kind: .time, equals: "fri at 7pm")
    }

    func testParsesTimeOnlyAsNextOccurrence() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 13, hour: 9, minute: 15)))

        let evening = QuickAddParser.parse("Dinner 6pm", calendar: calendar, now: now)
        XCTAssertEqual(evening.title, "Dinner")
        XCTAssertDate(evening.dueDate, year: 2026, month: 5, day: 13, hour: 18, minute: 0)

        let morning = QuickAddParser.parse("Coffee 6am", calendar: calendar, now: now)
        XCTAssertEqual(morning.title, "Coffee")
        XCTAssertDate(morning.dueDate, year: 2026, month: 5, day: 14, hour: 6, minute: 0)
    }

    func testParsesDaypartAsNextOccurrence() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 13, hour: 21, minute: 0)))
        let input = "Call Sam in the morning"

        let fields = QuickAddParser.parse(input, calendar: calendar, now: now)

        XCTAssertEqual(fields.title, "Call Sam")
        XCTAssertDate(fields.dueDate, year: 2026, month: 5, day: 14, hour: 9, minute: 0)
        XCTAssertToken(in: fields, originalText: input, kind: .time, equals: "in the morning")
    }

    func testParsesMonthDayFormats() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 13, hour: 9, minute: 15)))

        let namedMonth = QuickAddParser.parse("Book venue jan 27", calendar: calendar, now: now)
        XCTAssertEqual(namedMonth.title, "Book venue")
        XCTAssertDate(namedMonth.dueDate, year: 2027, month: 1, day: 27, hour: nil, minute: nil)

        let reversedMonth = QuickAddParser.parse("Book venue 27 jan", calendar: calendar, now: now)
        XCTAssertEqual(reversedMonth.title, "Book venue")
        XCTAssertDate(reversedMonth.dueDate, year: 2027, month: 1, day: 27, hour: nil, minute: nil)

        let ordinalDay = QuickAddParser.parse("Send invoice 27th", calendar: calendar, now: now)
        XCTAssertEqual(ordinalDay.title, "Send invoice")
        XCTAssertDate(ordinalDay.dueDate, year: 2026, month: 5, day: 27, hour: nil, minute: nil)

        let slashDate = QuickAddParser.parse("Renew permit 1/27", calendar: calendar, now: now)
        XCTAssertEqual(slashDate.title, "Renew permit")
        XCTAssertDate(slashDate.dueDate, year: 2027, month: 1, day: 27, hour: nil, minute: nil)
    }

    func testParsesWeekendAndLongerRelativeDates() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 13, hour: 9, minute: 15)))

        let laterThisWeek = QuickAddParser.parse("Prep memo later this week", calendar: calendar, now: now)
        XCTAssertEqual(laterThisWeek.title, "Prep memo")
        XCTAssertDate(laterThisWeek.dueDate, year: 2026, month: 5, day: 15, hour: nil, minute: nil)

        let thisWeekend = QuickAddParser.parse("Pack this weekend", calendar: calendar, now: now)
        XCTAssertEqual(thisWeekend.title, "Pack")
        XCTAssertDate(thisWeekend.dueDate, year: 2026, month: 5, day: 16, hour: nil, minute: nil)

        let nextWeekend = QuickAddParser.parse("Pack next weekend", calendar: calendar, now: now)
        XCTAssertEqual(nextWeekend.title, "Pack")
        XCTAssertDate(nextWeekend.dueDate, year: 2026, month: 5, day: 23, hour: nil, minute: nil)

        let nextMonth = QuickAddParser.parse("Review budget next month", calendar: calendar, now: now)
        XCTAssertEqual(nextMonth.title, "Review budget")
        XCTAssertDate(nextMonth.dueDate, year: 2026, month: 6, day: 13, hour: nil, minute: nil)
    }

    func testParsesDateMath() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 13, hour: 9, minute: 15)))

        let signedRelative = QuickAddParser.parse("Follow up +5 days", calendar: calendar, now: now)
        XCTAssertEqual(signedRelative.title, "Follow up")
        XCTAssertDate(signedRelative.dueDate, year: 2026, month: 5, day: 18, hour: nil, minute: nil)

        let daysFrom = QuickAddParser.parse("Check contract 17 days from jul 9", calendar: calendar, now: now)
        XCTAssertEqual(daysFrom.title, "Check contract")
        XCTAssertDate(daysFrom.dueDate, year: 2026, month: 7, day: 26, hour: nil, minute: nil)

        let weeksBefore = QuickAddParser.parse("Start prep 6 weeks before jul 21", calendar: calendar, now: now)
        XCTAssertEqual(weeksBefore.title, "Start prep")
        XCTAssertDate(weeksBefore.dueDate, year: 2026, month: 6, day: 9, hour: nil, minute: nil)
    }

    func testParsesInlineNotes() throws {
        let fields = QuickAddParser.parse("Call Sam tom // ask about renewal")

        XCTAssertEqual(fields.title, "Call Sam")
        XCTAssertEqual(fields.inlineNotes, "ask about renewal")
        XCTAssertNotNil(fields.dueDate)
        XCTAssertToken(in: fields, originalText: "Call Sam tom // ask about renewal", kind: .note, equals: "// ask about renewal")
    }

    func testLeavesAmbiguousRecurrenceWordsAsTitleText() throws {
        let monthly = QuickAddParser.parse("Create monthly report")
        XCTAssertEqual(monthly.title, "Create monthly report")
        XCTAssertNil(monthly.dueDate)

        let daily = QuickAddParser.parse("Review daily checklist")
        XCTAssertEqual(daily.title, "Review daily checklist")
        XCTAssertNil(daily.dueDate)
    }

    func testParsesDailyRecurrenceAtNextMatchingTime() throws {
        let now = try date(year: 2026, month: 5, day: 13, hour: 9, minute: 15)
        let input = "Take vitamins every day at 10am"

        let fields = QuickAddParser.parse(input, calendar: calendar, now: now)

        XCTAssertEqual(fields.title, "Take vitamins")
        XCTAssertEqual(fields.recurrence, ReminderRecurrence(frequency: .daily))
        XCTAssertDate(fields.dueDate, year: 2026, month: 5, day: 13, hour: 10, minute: 0)
        XCTAssertToken(in: fields, originalText: input, kind: .recurrence, equals: "every day at 10am")
    }

    func testDailyRecurrenceMovesPastElapsedTime() throws {
        let now = try date(year: 2026, month: 5, day: 13, hour: 9, minute: 15)

        let fields = QuickAddParser.parse("Take vitamins every day at 8am", calendar: calendar, now: now)

        XCTAssertDate(fields.dueDate, year: 2026, month: 5, day: 14, hour: 8, minute: 0)
    }

    func testParsesWeekdayAndNamedWeekdayRecurrences() throws {
        let now = try date(year: 2026, month: 5, day: 13, hour: 9, minute: 15)

        let weekdays = QuickAddParser.parse(
            "Review queue every weekday at 9am",
            calendar: calendar,
            now: now
        )
        let monday = QuickAddParser.parse(
            "Plan week every Monday at 5pm",
            calendar: calendar,
            now: now
        )

        XCTAssertEqual(
            weekdays.recurrence,
            ReminderRecurrence(
                frequency: .weekly,
                weekdays: [.monday, .tuesday, .wednesday, .thursday, .friday]
            )
        )
        XCTAssertDate(weekdays.dueDate, year: 2026, month: 5, day: 14, hour: 9, minute: 0)
        XCTAssertEqual(
            monday.recurrence,
            ReminderRecurrence(frequency: .weekly, weekdays: [.monday])
        )
        XCTAssertDate(monday.dueDate, year: 2026, month: 5, day: 18, hour: 17, minute: 0)
    }

    func testParsesIntervalRecurrence() throws {
        let now = try date(year: 2026, month: 5, day: 13, hour: 9, minute: 15)
        let input = "Water plants every 2 weeks"

        let fields = QuickAddParser.parse(input, calendar: calendar, now: now)

        XCTAssertEqual(fields.title, "Water plants")
        XCTAssertEqual(fields.recurrence, ReminderRecurrence(frequency: .weekly, interval: 2))
        XCTAssertDate(fields.dueDate, year: 2026, month: 5, day: 27, hour: nil, minute: nil)
        XCTAssertToken(in: fields, originalText: input, kind: .recurrence, equals: "every 2 weeks")
    }

    func testParsesDateBasedRecurrenceEnd() throws {
        let now = try date(year: 2026, month: 5, day: 13, hour: 9, minute: 15)
        let input = "Review plan every Monday at 9am until Sep 30"

        let fields = QuickAddParser.parse(input, calendar: calendar, now: now)

        XCTAssertEqual(fields.title, "Review plan")
        XCTAssertDate(fields.dueDate, year: 2026, month: 5, day: 18, hour: 9, minute: 0)

        guard case let .date(endDate)? = fields.recurrence?.end else {
            return XCTFail("Expected a date-based recurrence end")
        }

        XCTAssertDate(endDate, year: 2026, month: 9, day: 30, hour: nil, minute: nil)
        XCTAssertToken(
            in: fields,
            originalText: input,
            kind: .recurrence,
            equals: "every Monday at 9am until Sep 30"
        )
    }

    func testNamedRecurrenceEndRollsForwardFromFirstOccurrence() throws {
        let now = try date(year: 2026, month: 8, day: 12, hour: 9, minute: 15)
        let input = "Renew policy every year until Sep 30"

        let fields = QuickAddParser.parse(input, calendar: calendar, now: now)

        XCTAssertEqual(fields.title, "Renew policy")
        XCTAssertDate(fields.dueDate, year: 2027, month: 8, day: 12, hour: nil, minute: nil)

        guard case let .date(endDate)? = fields.recurrence?.end else {
            return XCTFail("Expected a date-based recurrence end")
        }

        XCTAssertDate(endDate, year: 2027, month: 9, day: 30, hour: nil, minute: nil)
        XCTAssertToken(
            in: fields,
            originalText: input,
            kind: .recurrence,
            equals: "every year until Sep 30"
        )
    }

    func testNamedDatesConsumeAnExplicitYear() throws {
        let now = try date(year: 2026, month: 8, day: 12, hour: 9, minute: 15)
        let recurrence = QuickAddParser.parse(
            "Review every Monday at 9am until Sep 30 2027",
            calendar: calendar,
            now: now
        )
        let oneOff = QuickAddParser.parse(
            "Review Sep 30 2027",
            calendar: calendar,
            now: now
        )

        XCTAssertEqual(recurrence.title, "Review")
        guard case let .date(endDate)? = recurrence.recurrence?.end else {
            return XCTFail("Expected a date-based recurrence end")
        }
        XCTAssertDate(endDate, year: 2027, month: 9, day: 30, hour: nil, minute: nil)
        XCTAssertEqual(oneOff.title, "Review")
        XCTAssertDate(oneOff.dueDate, year: 2027, month: 9, day: 30, hour: nil, minute: nil)
    }

    func testInvalidRecurrenceEndLeavesEntirePhraseAsTitleText() throws {
        let now = try date(year: 2026, month: 8, day: 12, hour: 9, minute: 15)
        let inputs = [
            "Review every day for 0 occurrences",
            "Review every day until Feb 30",
            "Review every year until 2026-09-30"
        ]

        for input in inputs {
            let fields = QuickAddParser.parse(input, calendar: calendar, now: now)

            XCTAssertEqual(fields.title, input)
            XCTAssertNil(fields.dueDate)
            XCTAssertNil(fields.recurrence)
            XCTAssertFalse(fields.usedTokens.contains { $0.kind == .recurrence })
        }
    }

    func testUnsupportedRecurrenceEndDoesNotBecomeDueDate() throws {
        let now = try date(year: 2026, month: 8, day: 12, hour: 9, minute: 15)
        let inputs = [
            "Review every Monday until tomorrow",
            "Review every Monday until 9/30",
            "Review every Monday until next week",
            "Review every Monday until Friday at 9am"
        ]

        for input in inputs {
            let fields = QuickAddParser.parse(input, calendar: calendar, now: now)

            XCTAssertEqual(fields.title, input)
            XCTAssertNil(fields.dueDate)
            XCTAssertNil(fields.recurrence)
        }
    }

    func testRejectsRecurrenceIntervalsThatEventKitCannotRepresent() throws {
        let now = try date(year: 2026, month: 8, day: 12, hour: 9, minute: 15)
        let input = "Boom every 2147483648 days"

        let fields = QuickAddParser.parse(input, calendar: calendar, now: now)

        XCTAssertEqual(fields.title, input)
        XCTAssertNil(fields.dueDate)
        XCTAssertNil(fields.recurrence)
    }

    func testLeapDayRecurrenceEndRollsForwardToNextValidYear() throws {
        let now = try date(year: 2026, month: 8, day: 12, hour: 9, minute: 15)

        let fields = QuickAddParser.parse(
            "Leap every year until Feb 29",
            calendar: calendar,
            now: now
        )

        XCTAssertEqual(fields.title, "Leap")
        XCTAssertDate(fields.dueDate, year: 2027, month: 8, day: 12, hour: nil, minute: nil)
        guard case let .date(endDate) = fields.recurrence?.end else {
            return XCTFail("Expected a date-based recurrence end")
        }
        XCTAssertDate(endDate, year: 2028, month: 2, day: 29, hour: nil, minute: nil)
    }

    func testSlashLeapDayRollsForwardToNextValidYear() throws {
        let now = try date(year: 2026, month: 8, day: 12, hour: 9, minute: 15)

        let fields = QuickAddParser.parse("Review 2/29", calendar: calendar, now: now)

        XCTAssertEqual(fields.title, "Review")
        XCTAssertDate(fields.dueDate, year: 2028, month: 2, day: 29, hour: nil, minute: nil)
    }

    func testParsesCountBasedRecurrenceEndAliases() throws {
        let now = try date(year: 2026, month: 5, day: 13, hour: 9, minute: 15)
        let occurrences = QuickAddParser.parse(
            "Review plan every 2 weeks for 6 occurrences",
            calendar: calendar,
            now: now
        )
        let times = QuickAddParser.parse(
            "Take vitamins every day at 10am for 3 times",
            calendar: calendar,
            now: now
        )

        XCTAssertEqual(occurrences.title, "Review plan")
        XCTAssertEqual(occurrences.recurrence?.end, .occurrenceCount(6))
        XCTAssertEqual(times.title, "Take vitamins")
        XCTAssertEqual(times.recurrence?.end, .occurrenceCount(3))
    }

    func testLeavesRecurrenceEndDateAsTitleTextWithoutRecurrence() throws {
        let now = try date(year: 2026, month: 5, day: 13, hour: 9, minute: 15)

        let fields = QuickAddParser.parse(
            "Review plan until Sep 30th",
            calendar: calendar,
            now: now
        )

        XCTAssertEqual(fields.title, "Review plan until Sep 30th")
        XCTAssertNil(fields.dueDate)
        XCTAssertNil(fields.recurrence)
    }

    func testParsesEarlyReminderLanguage() throws {
        let now = try date(year: 2026, month: 5, day: 13, hour: 9, minute: 15)
        let oneDay = QuickAddParser.parse(
            "Renew policy tomorrow at 10am remind 1d before",
            calendar: calendar,
            now: now
        )
        let twoHours = QuickAddParser.parse(
            "Join review tomorrow at 2pm remind me 2h before",
            calendar: calendar,
            now: now
        )
        let thirtyMinutes = QuickAddParser.parse(
            "Submit report tomorrow at 10am remind 30m early",
            calendar: calendar,
            now: now
        )

        XCTAssertEqual(oneDay.title, "Renew policy")
        XCTAssertEqual(oneDay.earlyReminder, ReminderEarlyReminder(amount: 1, unit: .days))
        XCTAssertDate(oneDay.dueDate, year: 2026, month: 5, day: 14, hour: 10, minute: 0)
        XCTAssertEqual(twoHours.title, "Join review")
        XCTAssertEqual(twoHours.earlyReminder, ReminderEarlyReminder(amount: 2, unit: .hours))
        XCTAssertEqual(thirtyMinutes.title, "Submit report")
        XCTAssertEqual(
            thirtyMinutes.earlyReminder,
            ReminderEarlyReminder(amount: 30, unit: .minutes)
        )
    }

    func testParsesEarlyReminderBeforeTimedSchedule() throws {
        let now = try date(year: 2026, month: 8, day: 12, hour: 9, minute: 15)

        let fields = QuickAddParser.parse(
            "Review remind 2h early tomorrow at 5pm",
            calendar: calendar,
            now: now
        )

        XCTAssertEqual(fields.title, "Review")
        XCTAssertDate(fields.dueDate, year: 2026, month: 8, day: 13, hour: 17, minute: 0)
        XCTAssertEqual(fields.earlyReminder, ReminderEarlyReminder(amount: 2, unit: .hours))
    }

    func testEarlyReminderWithoutTimedScheduleCannotBecomeDueDate() throws {
        let now = try date(year: 2026, month: 8, day: 12, hour: 9, minute: 15)
        let input = "Review remind 2h early"

        let fields = QuickAddParser.parse(input, calendar: calendar, now: now)

        XCTAssertEqual(fields.title, input)
        XCTAssertNil(fields.dueDate)
        XCTAssertNil(fields.earlyReminder)
    }

    func testParsesStandaloneHTTPURL() {
        let input = "Read proposal https://example.com/proposal?tab=summary #Work"

        let fields = QuickAddParser.parse(input, calendar: calendar)

        XCTAssertEqual(fields.title, "Read proposal")
        XCTAssertEqual(fields.url, URL(string: "https://example.com/proposal?tab=summary"))
        XCTAssertEqual(fields.listName, "Work")
        XCTAssertToken(
            in: fields,
            originalText: input,
            kind: .url,
            equals: "https://example.com/proposal?tab=summary"
        )
    }

    func testTrimsExternalURLPunctuation() {
        let cases = [
            ("https://example.com/report,", "https://example.com/report"),
            ("https://example.com/report.", "https://example.com/report"),
            ("https://example.com/report)", "https://example.com/report"),
            ("https://example.com/report_(final)", "https://example.com/report_(final)")
        ]

        for (inputURL, expectedURL) in cases {
            let input = "Read proposal \(inputURL)"
            let fields = QuickAddParser.parse(input, calendar: calendar)

            XCTAssertEqual(fields.title, "Read proposal")
            XCTAssertEqual(fields.url, URL(string: expectedURL))
            XCTAssertToken(
                in: fields,
                originalText: input,
                kind: .url,
                equals: expectedURL
            )
        }
    }

    func testParsesURLInsideParentheses() {
        let input = "Open (https://example.com/report)"

        let fields = QuickAddParser.parse(input, calendar: calendar)

        XCTAssertEqual(fields.title, "Open")
        XCTAssertEqual(fields.url, URL(string: "https://example.com/report"))
        XCTAssertToken(
            in: fields,
            originalText: input,
            kind: .url,
            equals: "https://example.com/report"
        )
    }

    func testParsesRecurrenceEarlyReminderAndURLTogether() throws {
        let now = try date(year: 2026, month: 5, day: 13, hour: 9, minute: 15)
        let input = "Review metrics every Monday at 9am remind 30m early https://example.com/metrics"

        let fields = QuickAddParser.parse(input, calendar: calendar, now: now)

        XCTAssertEqual(fields.title, "Review metrics")
        XCTAssertEqual(
            fields.recurrence,
            ReminderRecurrence(frequency: .weekly, weekdays: [.monday])
        )
        XCTAssertEqual(fields.earlyReminder, ReminderEarlyReminder(amount: 30, unit: .minutes))
        XCTAssertEqual(fields.url, URL(string: "https://example.com/metrics"))
        XCTAssertDate(fields.dueDate, year: 2026, month: 5, day: 18, hour: 9, minute: 0)
        XCTAssertToken(in: fields, originalText: input, kind: .earlyReminder, equals: "remind 30m early")
    }

    func testLeavesEarlyReminderAsTitleTextWithoutTimedDueDate() throws {
        let now = try date(year: 2026, month: 5, day: 13, hour: 9, minute: 15)

        let fields = QuickAddParser.parse(
            "Renew policy tomorrow remind 1d before",
            calendar: calendar,
            now: now
        )

        XCTAssertEqual(fields.title, "Renew policy remind 1d before")
        XCTAssertNil(fields.earlyReminder)
    }

    func testDueDateEditorClearsRecurrence() throws {
        let now = try date(year: 2026, month: 5, day: 13, hour: 9, minute: 15)
        let input = "Standup every Monday at 9am #Work"

        let output = QuickAddDueDateTokenEditor.applying(
            nil,
            to: input,
            calendar: calendar,
            now: now
        )

        XCTAssertEqual(output, "Standup #Work")
    }

    func testEarlyReminderRequiresTheFinalSelectedDueDateToIncludeTime() throws {
        let now = try date(year: 2026, month: 8, day: 12, hour: 9, minute: 15)
        let notesInput = "Review remind 2h early // tomorrow at 5pm"
        let dateOnlyInput = "Review remind 2h early tomorrow for the meeting at 5pm"

        let notes = QuickAddParser.parse(notesInput, calendar: calendar, now: now)
        let dateOnly = QuickAddParser.parse(dateOnlyInput, calendar: calendar, now: now)

        XCTAssertEqual(notes.title, "Review remind 2h early")
        XCTAssertEqual(notes.inlineNotes, "tomorrow at 5pm")
        XCTAssertNil(notes.dueDate)
        XCTAssertNil(notes.earlyReminder)
        XCTAssertEqual(dateOnly.title, "Review remind 2h early for the meeting at 5pm")
        XCTAssertDate(dateOnly.dueDate, year: 2026, month: 8, day: 13, hour: nil, minute: nil)
        XCTAssertNil(dateOnly.earlyReminder)
    }

    func testInvalidRecurrenceKeepsItsAssociatedTimeLiteral() throws {
        let now = try date(year: 2026, month: 8, day: 12, hour: 9, minute: 15)
        let inputs = [
            "Boom every 2147483648 days at 9am",
            "Boom every 2147483648 days https://example.com at 9am",
            "Boom every 2147483648 days remind 30m early at 9am",
            "Review every Monday until tomorrow at 9am",
            "Review every day for 10001 occurrences at 9am"
        ]

        for input in inputs {
            let fields = QuickAddParser.parse(input, calendar: calendar, now: now)

            XCTAssertEqual(fields.title, input)
            XCTAssertNil(fields.dueDate)
            XCTAssertNil(fields.recurrence)
        }
    }

    func testUnsupportedRecurrenceGrammarCannotLeakAOneOffSchedule() throws {
        let now = try date(year: 2026, month: 8, day: 12, hour: 9, minute: 15)
        let inputs = [
            "Review every other day at 9am",
            "Review every Monday and Wednesday at 9am",
            "Review every Monday at 9am and Wednesday",
            "Review every Monday at 9am or Wednesday at 5pm",
            "Review every Monday until Sep 30 and Wednesday"
        ]

        for input in inputs {
            let fields = QuickAddParser.parse(input, calendar: calendar, now: now)

            XCTAssertEqual(fields.title, input)
            XCTAssertNil(fields.dueDate)
            XCTAssertNil(fields.recurrence)
        }
    }

    func testLateCalendarUnitRecurrencesPreserveTheirRequestedDay() throws {
        let monthNow = try date(year: 2027, month: 1, day: 31, hour: 9, minute: 15)
        let monthly = QuickAddParser.parse(
            "Review every month for 2 occurrences",
            calendar: calendar,
            now: monthNow
        )

        XCTAssertDate(monthly.dueDate, year: 2027, month: 3, day: 31, hour: nil, minute: nil)
        let monthlyEnd = try XCTUnwrap(ReminderRecurrenceCalculator.finalOccurrenceDate(
            startingAt: try XCTUnwrap(monthly.dueDate),
            recurrence: try XCTUnwrap(monthly.recurrence),
            occurrenceCount: 2
        ))
        let monthlyEndComponents = calendar.dateComponents([.year, .month, .day], from: monthlyEnd)
        XCTAssertDate(
            monthlyEndComponents,
            year: 2027,
            month: 5,
            day: 31,
            hour: nil,
            minute: nil
        )

        let leapNow = try date(year: 2028, month: 2, day: 29, hour: 9, minute: 15)
        let yearly = QuickAddParser.parse(
            "Review every year for 2 occurrences",
            calendar: calendar,
            now: leapNow
        )

        XCTAssertDate(yearly.dueDate, year: 2032, month: 2, day: 29, hour: nil, minute: nil)
        let yearlyEnd = try XCTUnwrap(ReminderRecurrenceCalculator.finalOccurrenceDate(
            startingAt: try XCTUnwrap(yearly.dueDate),
            recurrence: try XCTUnwrap(yearly.recurrence),
            occurrenceCount: 2
        ))
        let yearlyEndComponents = calendar.dateComponents([.year, .month, .day], from: yearlyEnd)
        XCTAssertDate(
            yearlyEndComponents,
            year: 2036,
            month: 2,
            day: 29,
            hour: nil,
            minute: nil
        )
    }

    func testDueDateEditorReplacesScheduleAfterEarlyReminder() throws {
        let now = try date(year: 2026, month: 8, day: 12, hour: 9, minute: 15)
        let selectionDate = try date(year: 2026, month: 8, day: 14, hour: 15, minute: 0)
        let input = "Review remind 2h early tomorrow at 5pm"

        let output = QuickAddDueDateTokenEditor.applying(
            QuickAddDueDateSelection(date: selectionDate, includesTime: true),
            to: input,
            calendar: calendar,
            now: now
        )
        let fields = QuickAddParser.parse(output, calendar: calendar, now: now)

        XCTAssertEqual(output, "Review remind 2h early 2026-08-14 3:00pm")
        XCTAssertEqual(fields.title, "Review")
        XCTAssertDate(fields.dueDate, year: 2026, month: 8, day: 14, hour: 15, minute: 0)
        XCTAssertEqual(fields.earlyReminder, ReminderEarlyReminder(amount: 2, unit: .hours))
    }

    func testRecurrenceEndCanFollowOtherMetadata() throws {
        let now = try date(year: 2026, month: 8, day: 12, hour: 9, minute: 15)
        let inputs = [
            "Review metrics every Monday at 9am remind 30m early until Sep 30 https://example.com",
            "Review metrics every Monday at 9am https://example.com until Sep 30"
        ]

        for input in inputs {
            let fields = QuickAddParser.parse(input, calendar: calendar, now: now)

            XCTAssertEqual(fields.title, "Review metrics")
            XCTAssertEqual(fields.url, URL(string: "https://example.com"))
            guard case let .date(endDate)? = fields.recurrence?.end else {
                return XCTFail("Expected a date-based recurrence end")
            }
            XCTAssertDate(endDate, year: 2026, month: 9, day: 30, hour: nil, minute: nil)
        }
    }

    func testRecurrenceEndCanFollowListTagAndPriorityMetadata() throws {
        let now = try date(year: 2026, month: 8, day: 12, hour: 9, minute: 15)
        let inputs = [
            "Review every Monday at 9am #Work until Sep 30",
            "Review every Monday at 9am @work until Sep 30",
            "Review every Monday at 9am P1 until Sep 30"
        ]

        for input in inputs {
            let fields = QuickAddParser.parse(input, calendar: calendar, now: now)

            XCTAssertEqual(fields.title, "Review")
            guard case let .date(endDate)? = fields.recurrence?.end else {
                return XCTFail("Expected a date-based recurrence end")
            }
            XCTAssertDate(endDate, year: 2026, month: 9, day: 30, hour: nil, minute: nil)
        }
    }

    func testScheduleTimeCanFollowOtherMetadata() throws {
        let now = try date(year: 2026, month: 8, day: 12, hour: 9, minute: 15)
        let oneOff = QuickAddParser.parse(
            "Review tomorrow #Work at 9am",
            calendar: calendar,
            now: now
        )
        let recurrence = QuickAddParser.parse(
            "Review every Monday #Work at 9am until Sep 30",
            calendar: calendar,
            now: now
        )

        XCTAssertEqual(oneOff.title, "Review")
        XCTAssertEqual(oneOff.listName, "Work")
        XCTAssertDate(oneOff.dueDate, year: 2026, month: 8, day: 13, hour: 9, minute: 0)
        XCTAssertEqual(recurrence.title, "Review")
        XCTAssertEqual(recurrence.listName, "Work")
        XCTAssertDate(recurrence.dueDate, year: 2026, month: 8, day: 17, hour: 9, minute: 0)
        guard case let .date(endDate)? = recurrence.recurrence?.end else {
            return XCTFail("Expected a date-based recurrence end")
        }
        XCTAssertDate(endDate, year: 2026, month: 9, day: 30, hour: nil, minute: nil)
    }

    func testRecurrenceTimeCanFollowItsEndClause() throws {
        let now = try date(year: 2026, month: 8, day: 12, hour: 9, minute: 15)
        let fields = QuickAddParser.parse(
            "Review every Monday until Sep 30 at 9am",
            calendar: calendar,
            now: now
        )

        XCTAssertEqual(fields.title, "Review")
        XCTAssertDate(fields.dueDate, year: 2026, month: 8, day: 17, hour: 9, minute: 0)
    }

    func testRejectsFiniteRecurrenceWhoseFinalOccurrenceCannotBeRepresented() throws {
        let now = try date(year: 2026, month: 8, day: 12, hour: 9, minute: 15)
        let input = "Archive every 100 years for 10000 occurrences"

        let fields = QuickAddParser.parse(input, calendar: calendar, now: now)

        XCTAssertEqual(fields.title, input)
        XCTAssertNil(fields.dueDate)
        XCTAssertNil(fields.recurrence)
    }

    func testParsesMarkdownLinkDestinationWithoutCombiningURLs() {
        let input = "Open [https://example.com/report](https://example.com/report)"

        let fields = QuickAddParser.parse(input, calendar: calendar)

        XCTAssertEqual(fields.title, "Open")
        XCTAssertEqual(fields.url, URL(string: "https://example.com/report"))
        XCTAssertToken(
            in: fields,
            originalText: input,
            kind: .url,
            equals: "[https://example.com/report](https://example.com/report)"
        )
    }

    func testMarkdownURLIgnoresSentencePunctuationAndExtraClosingDelimiter() {
        let inputs = [
            "Open [report](https://example.com/report)?",
            "Open [report](https://example.com/report))"
        ]

        for input in inputs {
            let fields = QuickAddParser.parse(input, calendar: calendar)

            XCTAssertEqual(fields.title, "Open")
            XCTAssertEqual(fields.url, URL(string: "https://example.com/report"))
        }
    }

    func testDSTGapTimeNormalizesOnceWithoutChangingARecurrence() throws {
        var losAngelesCalendar = Calendar(identifier: .gregorian)
        losAngelesCalendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let now = try XCTUnwrap(losAngelesCalendar.date(from: DateComponents(
            calendar: losAngelesCalendar,
            timeZone: losAngelesCalendar.timeZone,
            year: 2027,
            month: 3,
            day: 13,
            hour: 10,
            minute: 0
        )))
        let oneOff = QuickAddParser.parse(
            "Review tomorrow at 2:30am",
            calendar: losAngelesCalendar,
            now: now
        )
        let recurrence = QuickAddParser.parse(
            "Review every day at 2:30am for 2 occurrences",
            calendar: losAngelesCalendar,
            now: now
        )

        XCTAssertDate(oneOff.dueDate, year: 2027, month: 3, day: 14, hour: 3, minute: 30)
        XCTAssertDate(recurrence.dueDate, year: 2027, month: 3, day: 15, hour: 2, minute: 30)
        let finalOccurrence = try XCTUnwrap(ReminderRecurrenceCalculator.finalOccurrenceDate(
            startingAt: try XCTUnwrap(recurrence.dueDate),
            recurrence: try XCTUnwrap(recurrence.recurrence),
            occurrenceCount: 2
        ))
        let finalComponents = losAngelesCalendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: finalOccurrence
        )
        XCTAssertDate(finalComponents, year: 2027, month: 3, day: 16, hour: 2, minute: 30)
    }

    func testSentencePunctuationDoesNotBecomeMetadataValue() throws {
        let now = try date(year: 2026, month: 8, day: 12, hour: 9, minute: 15)
        let list = QuickAddParser.parse("Review #Work, tomorrow", calendar: calendar, now: now)
        let tag = QuickAddParser.parse("Review @work, tomorrow", calendar: calendar, now: now)
        let priority = QuickAddParser.parse("Review P1, tomorrow", calendar: calendar, now: now)

        XCTAssertEqual(list.listName, "Work")
        XCTAssertEqual(tag.tags, ["work"])
        XCTAssertEqual(priority.priority, 1)
    }

    func testURLPreservesATrailingQuestionMarkInsideAQuery() {
        let fields = QuickAddParser.parse(
            "Review https://example.com/search?q=why?",
            calendar: calendar
        )

        XCTAssertEqual(fields.title, "Review")
        XCTAssertEqual(fields.url?.absoluteString, "https://example.com/search?q=why?")
    }

    func testSentencePunctuationDoesNotBreakReminderMetadata() throws {
        let now = try date(year: 2026, month: 8, day: 12, hour: 9, minute: 15)
        let recurrence = QuickAddParser.parse(
            "Review metrics every Monday!",
            calendar: calendar,
            now: now
        )
        let earlyReminder = QuickAddParser.parse(
            "Submit tomorrow at 10am remind 30m early!",
            calendar: calendar,
            now: now
        )

        XCTAssertEqual(recurrence.title, "Review metrics")
        XCTAssertEqual(
            recurrence.recurrence,
            ReminderRecurrence(frequency: .weekly, weekdays: [.monday])
        )
        XCTAssertEqual(earlyReminder.title, "Submit")
        XCTAssertEqual(
            earlyReminder.earlyReminder,
            ReminderEarlyReminder(amount: 30, unit: .minutes)
        )
    }

    func testCanSuppressRecognizedDateToken() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 13, hour: 9, minute: 15)))
        let input = "Dinner 6pm"
        let parsed = QuickAddParser.parse(input, calendar: calendar, now: now)
        let token = try XCTUnwrap(parsed.usedTokens.first)

        let suppressed = QuickAddParser.parse(
            input,
            calendar: calendar,
            now: now,
            suppressedTokens: [
                QuickAddSuppressedToken(
                    kind: token.kind,
                    range: token.range,
                    text: (input as NSString).substring(with: token.range)
                )
            ]
        )

        XCTAssertEqual(suppressed.title, "Dinner 6pm")
        XCTAssertNil(suppressed.dueDate)
        XCTAssertTrue(suppressed.usedTokens.isEmpty)
    }

    private func XCTAssertDate(
        _ components: DateComponents?,
        year: Int,
        month: Int,
        day: Int,
        hour: Int?,
        minute: Int?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(components?.year, year, file: file, line: line)
        XCTAssertEqual(components?.month, month, file: file, line: line)
        XCTAssertEqual(components?.day, day, file: file, line: line)
        XCTAssertEqual(components?.hour, hour, file: file, line: line)
        XCTAssertEqual(components?.minute, minute, file: file, line: line)
    }

    private func XCTAssertToken(
        in fields: QuickAddFields,
        originalText: String,
        kind: QuickAddToken.Kind,
        equals expectedText: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let token = fields.usedTokens.first(where: { $0.kind == kind }) else {
            XCTFail("Missing token of kind \(kind)", file: file, line: line)
            return
        }

        XCTAssertEqual((originalText as NSString).substring(with: token.range), expectedText, file: file, line: line)
    }

    private func date(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> Date {
        try XCTUnwrap(
            calendar.date(from: DateComponents(
                calendar: calendar,
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute
            )),
            file: file,
            line: line
        )
    }
}
