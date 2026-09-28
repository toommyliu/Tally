import EventKit
import XCTest
@testable import Tally

final class CalendarEventEventKitMapperTests: XCTestCase {
    private let eventStore = EKEventStore()
    private var dateCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }()

    func testTimedEventKeepsItsTimesZoneAlertAndNotes() throws {
        let request = makeRequest(
            timing: CalendarEventTiming(
                start: components(day: 1, hour: 14, minute: 0),
                end: components(day: 1, hour: 14, minute: 45),
                isAllDay: false
            ),
            alert: ReminderEarlyReminder(amount: 30, unit: .minutes)
        )
        let event = EKEvent(eventStore: eventStore)

        try CalendarEventEventKitMapper.populate(
            event,
            from: request,
            calendar: makeCalendar(),
            dateCalendar: dateCalendar
        )

        XCTAssertEqual(event.title, "Design review")
        XCTAssertFalse(event.isAllDay)
        XCTAssertEqual(event.timeZone, dateCalendar.timeZone)
        XCTAssertEqual(event.endDate.timeIntervalSince(event.startDate), 45 * 60)
        XCTAssertEqual(dateCalendar.component(.hour, from: event.startDate), 14)
        XCTAssertEqual(event.alarms?.map(\.relativeOffset), [-30 * 60])
        XCTAssertEqual(event.url, URL(string: "https://meet.example.com/abc"))
        XCTAssertEqual(event.notes, "Bring notes\nTags: @design")
    }

    func testAllDayEventFloatsWithoutATimeZone() throws {
        let request = makeRequest(
            timing: CalendarEventTiming(
                start: components(day: 2, hour: nil, minute: nil),
                end: components(day: 4, hour: nil, minute: nil),
                isAllDay: true
            )
        )
        let event = EKEvent(eventStore: eventStore)

        try CalendarEventEventKitMapper.populate(
            event,
            from: request,
            calendar: makeCalendar(),
            dateCalendar: dateCalendar
        )

        XCTAssertTrue(event.isAllDay)
        XCTAssertNil(event.timeZone)
        XCTAssertEqual(Calendar.current.component(.day, from: event.startDate), 2)
        XCTAssertEqual(Calendar.current.component(.day, from: event.endDate), 4)
    }

    func testRecurringEventKeepsItsOccurrenceCount() throws {
        let request = makeRequest(
            timing: CalendarEventTiming(
                start: components(day: 5, hour: 9, minute: 0),
                end: components(day: 5, hour: 10, minute: 0),
                isAllDay: false
            ),
            recurrence: ReminderRecurrence(frequency: .weekly, weekdays: [.monday], end: .occurrenceCount(6))
        )
        let event = EKEvent(eventStore: eventStore)

        try CalendarEventEventKitMapper.populate(
            event,
            from: request,
            calendar: makeCalendar(),
            dateCalendar: dateCalendar
        )

        let rule = try XCTUnwrap(event.recurrenceRules?.first)
        XCTAssertEqual(rule.frequency, .weekly)
        XCTAssertEqual(rule.recurrenceEnd?.occurrenceCount, 6)
        XCTAssertNil(rule.recurrenceEnd?.endDate)
    }

    func testAlertOffsetsCoverEveryUnit() {
        XCTAssertEqual(CalendarEventEventKitMapper.offset(for: .init(amount: 2, unit: .hours)), 7_200)
        XCTAssertEqual(CalendarEventEventKitMapper.offset(for: .init(amount: 1, unit: .days)), 86_400)
        XCTAssertEqual(CalendarEventEventKitMapper.offset(for: .init(amount: 1, unit: .weeks)), 604_800)
    }

    private func makeCalendar() -> EKCalendar {
        EKCalendar(for: .event, eventStore: eventStore)
    }

    private func components(day: Int, hour: Int?, minute: Int?) -> DateComponents {
        DateComponents(
            calendar: dateCalendar,
            timeZone: dateCalendar.timeZone,
            year: 2026,
            month: 10,
            day: day,
            hour: hour,
            minute: minute
        )
    }

    private func makeRequest(
        timing: CalendarEventTiming,
        recurrence: ReminderRecurrence? = nil,
        alert: ReminderEarlyReminder? = nil
    ) -> CalendarEventCreationRequest {
        CalendarEventCreationRequest(
            title: "Design review",
            userNotes: "Bring notes",
            inlineNotes: nil,
            tags: ["design"],
            calendarIdentifier: nil,
            calendarName: nil,
            timing: timing,
            recurrence: recurrence,
            alert: alert,
            url: URL(string: "https://meet.example.com/abc")
        )
    }
}
