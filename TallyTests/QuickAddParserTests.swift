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

    func testDueDateTokenEditorRespectsSuppressedInferredTokens() throws {
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
            suppressedInferredTokens: [
                QuickAddSuppressedToken(
                    kind: token.kind,
                    range: token.range,
                    text: (input as NSString).substring(with: token.range)
                )
            ]
        )

        XCTAssertEqual(output, "Dinner 6pm 2026-08-14")
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

    func testCanSuppressInferredDateToken() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 13, hour: 9, minute: 15)))
        let input = "Dinner 6pm"
        let parsed = QuickAddParser.parse(input, calendar: calendar, now: now)
        let token = try XCTUnwrap(parsed.usedTokens.first)

        let suppressed = QuickAddParser.parse(
            input,
            calendar: calendar,
            now: now,
            suppressedInferredTokens: [
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
