import EventKit
import XCTest
@testable import Tally

final class ReminderCreationRequestTests: XCTestCase {
    func testMissingConfiguredListDoesNotFallBackToDefault() {
        let inbox = ReminderListInfo(id: "inbox-id", title: "Inbox")
        let request = makeRequest(listIdentifier: "deleted-list-id")

        let resolved = ReminderDestinationResolver.resolve(
            request: request,
            writableDestinations: [inbox],
            defaultDestination: inbox,
            identifier: \.id,
            title: \.title
        )

        XCTAssertNil(resolved)
    }

    func testAutomaticDestinationStillUsesDefaultList() {
        let inbox = ReminderListInfo(id: "inbox-id", title: "Inbox")
        let request = makeRequest()

        let resolved = ReminderDestinationResolver.resolve(
            request: request,
            writableDestinations: [inbox],
            defaultDestination: inbox,
            identifier: \.id,
            title: \.title
        )

        XCTAssertEqual(resolved, inbox)
    }

    func testCombinedNotesTrimsInputAndPreservesInlineNotesAndTags() {
        let request = makeRequest(
            userNotes: "  Supporting context\n",
            inlineNotes: "Ask about renewal",
            tags: ["phone", "follow-up"]
        )

        XCTAssertEqual(
            request.combinedNotes,
            "Supporting context\nAsk about renewal\nTags: @phone @follow-up"
        )
    }

    func testCombinedNotesDoesNotDuplicateMatchingInlineNotes() {
        let request = makeRequest(
            userNotes: "Ask about renewal",
            inlineNotes: "  Ask about renewal  "
        )

        XCTAssertEqual(request.combinedNotes, "Ask about renewal")
    }

    func testEventKitRecurrenceMappingConvertsOccurrenceCountToFinalDate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let start = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 8,
            day: 24
        )
        let recurrence = ReminderRecurrence(
            frequency: .weekly,
            interval: 2,
            weekdays: [.monday, .thursday],
            end: .occurrenceCount(6)
        )

        let rule = try XCTUnwrap(ReminderEventKitMapper.recurrenceRule(
            for: recurrence,
            startingAt: start
        ))
        let endDate = try XCTUnwrap(rule.recurrenceEnd?.endDate)
        let endComponents = calendar.dateComponents([.year, .month, .day], from: endDate)

        XCTAssertEqual(rule.frequency, .weekly)
        XCTAssertEqual(rule.interval, 2)
        XCTAssertEqual(rule.daysOfTheWeek?.map(\.dayOfTheWeek), [.monday, .thursday])
        XCTAssertEqual(endComponents.year, 2026)
        XCTAssertEqual(endComponents.month, 9)
        XCTAssertEqual(endComponents.day, 24)
    }

    func testOccurrenceCountIncludesEachSelectedWeekday() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let start = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 8,
            day: 13
        )
        let recurrence = ReminderRecurrence(
            frequency: .weekly,
            weekdays: [.monday, .tuesday, .wednesday, .thursday, .friday],
            end: .occurrenceCount(6)
        )

        let rule = try XCTUnwrap(ReminderEventKitMapper.recurrenceRule(
            for: recurrence,
            startingAt: start
        ))
        let endDate = try XCTUnwrap(rule.recurrenceEnd?.endDate)
        let endComponents = calendar.dateComponents([.year, .month, .day], from: endDate)

        XCTAssertEqual(endComponents.year, 2026)
        XCTAssertEqual(endComponents.month, 8)
        XCTAssertEqual(endComponents.day, 20)
    }

    func testEventKitRecurrenceMappingIncludesEntireEndDate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let components = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 9,
            day: 30
        )
        let recurrence = ReminderRecurrence(
            frequency: .daily,
            end: .date(components)
        )

        let rule = try XCTUnwrap(ReminderEventKitMapper.recurrenceRule(for: recurrence))
        let endDate = try XCTUnwrap(rule.recurrenceEnd?.endDate)
        let mapped = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: endDate
        )

        XCTAssertEqual(mapped.year, 2026)
        XCTAssertEqual(mapped.month, 9)
        XCTAssertEqual(mapped.day, 30)
        XCTAssertEqual(mapped.hour, 23)
        XCTAssertEqual(mapped.minute, 59)
        XCTAssertEqual(mapped.second, 59)
    }

    func testEventKitRecurrenceMappingRejectsUnsupportedIntervals() {
        let recurrence = ReminderRecurrence(
            frequency: .daily,
            interval: ReminderRecurrence.maximumInterval + 1
        )

        XCTAssertNil(ReminderEventKitMapper.recurrenceRule(for: recurrence))
    }

    func testEventKitRecurrenceMappingRejectsUnrepresentableFiniteEnd() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let start = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2126,
            month: 8,
            day: 12
        )
        let recurrence = ReminderRecurrence(
            frequency: .yearly,
            interval: 100,
            end: .occurrenceCount(10_000)
        )

        XCTAssertNil(ReminderEventKitMapper.recurrenceRule(
            for: recurrence,
            startingAt: start
        ))
    }

    private func makeRequest(
        userNotes: String? = nil,
        inlineNotes: String? = nil,
        tags: [String] = [],
        listIdentifier: String? = nil,
        listName: String? = nil
    ) -> ReminderCreationRequest {
        ReminderCreationRequest(
            title: "Call Sam",
            userNotes: userNotes,
            inlineNotes: inlineNotes,
            tags: tags,
            listIdentifier: listIdentifier,
            listName: listName,
            dueDate: nil,
            recurrence: nil,
            earlyReminder: nil,
            url: nil,
            priority: 0
        )
    }
}
