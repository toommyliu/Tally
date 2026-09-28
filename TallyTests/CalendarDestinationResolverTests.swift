import XCTest
@testable import Tally

final class CalendarDestinationResolverTests: XCTestCase {
    private let inbox = ReminderListInfo(id: "inbox-id", title: "Inbox")
    private let work = ReminderListInfo(id: "work-id", title: "Wörk")

    func testMissingConfiguredDestinationDoesNotFallBackToDefault() {
        let resolved = resolve(CalendarDestinationQuery(identifier: "deleted-id", name: nil))

        XCTAssertNil(resolved)
    }

    func testAutomaticDestinationUsesDefault() {
        let resolved = resolve(CalendarDestinationQuery(identifier: nil, name: nil))

        XCTAssertEqual(resolved, inbox)
    }

    func testAutomaticDestinationFallsBackToFirstWritableWithoutDefault() {
        let resolved = CalendarDestinationResolver.resolve(
            CalendarDestinationQuery(identifier: nil, name: nil),
            in: [work, inbox],
            default: nil,
            identifier: \.id,
            title: \.title
        )

        XCTAssertEqual(resolved, work)
    }

    func testNameMatchesIgnoringCaseAndDiacritics() {
        let resolved = resolve(CalendarDestinationQuery(identifier: nil, name: "work"))

        XCTAssertEqual(resolved, work)
    }

    func testUnknownNameDoesNotFallBackToDefault() {
        let resolved = resolve(CalendarDestinationQuery(identifier: nil, name: "Errands"))

        XCTAssertNil(resolved)
    }

    func testIdentifierTakesPrecedenceOverName() {
        let resolved = resolve(CalendarDestinationQuery(identifier: "inbox-id", name: "Work"))

        XCTAssertEqual(resolved, inbox)
    }

    func testReminderRequestBuildsDestinationQuery() {
        let request = ReminderCreationRequest(
            title: "Call Sam",
            userNotes: nil,
            inlineNotes: nil,
            tags: [],
            listIdentifier: nil,
            listName: "Work",
            dueDate: nil,
            recurrence: nil,
            earlyReminder: nil,
            url: nil,
            priority: 0
        )

        XCTAssertEqual(request.destination, CalendarDestinationQuery(identifier: nil, name: "Work"))
        XCTAssertTrue(request.destination.isSpecific)
    }

    private func resolve(_ query: CalendarDestinationQuery) -> ReminderListInfo? {
        CalendarDestinationResolver.resolve(
            query,
            in: [inbox, work],
            default: inbox,
            identifier: \.id,
            title: \.title
        )
    }
}
