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

    func testTomorrowAliasUsesNextDay() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 12, day: 31)))

        let fields = QuickAddParser.parse("Renew license tmr p2", calendar: calendar, now: now)

        XCTAssertEqual(fields.title, "Renew license")
        XCTAssertEqual(fields.priority, 5)
        XCTAssertEqual(fields.dueDate?.year, 2027)
        XCTAssertEqual(fields.dueDate?.month, 1)
        XCTAssertEqual(fields.dueDate?.day, 1)
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
}
