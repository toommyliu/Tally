import XCTest
@testable import Tally

final class QuickAddParserTests: XCTestCase {
    func testParsesTodoistStyleMetadata() throws {
        let calendar = Calendar(identifier: .gregorian)
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
        let calendar = Calendar(identifier: .gregorian)
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 12, day: 31)))

        let fields = QuickAddParser.parse("Renew license tmr p2", calendar: calendar, now: now)

        XCTAssertEqual(fields.title, "Renew license")
        XCTAssertEqual(fields.priority, 5)
        XCTAssertEqual(fields.dueDate?.year, 2027)
        XCTAssertEqual(fields.dueDate?.month, 1)
        XCTAssertEqual(fields.dueDate?.day, 1)
    }

    func testParsesDueTimeAfterDateToken() throws {
        let calendar = Calendar(identifier: .gregorian)
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
}
