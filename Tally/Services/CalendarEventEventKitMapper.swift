import EventKit

/// Converts Tally's event creation values into their EventKit representation.
enum CalendarEventEventKitMapper {
    static func populate(
        _ event: EKEvent,
        from request: CalendarEventCreationRequest,
        calendar: EKCalendar,
        dateCalendar: Calendar = .current
    ) throws {
        let isAllDay = request.timing.isAllDay
        var placementCalendar = dateCalendar
        if isAllDay { placementCalendar.timeZone = .current }
        guard let dates = request.timing.eventKitDates(in: placementCalendar) else {
            throw CalendarEventMappingError.invalidDates
        }
        guard !isAllDay || request.alert == nil else { throw CalendarEventMappingError.invalidAlert }

        event.title = request.title
        event.calendar = calendar
        event.isAllDay = isAllDay
        // All-day events float with the viewer; timed events keep the zone they were typed in.
        event.timeZone = isAllDay ? nil : request.timing.start.timeZone ?? dateCalendar.timeZone
        event.startDate = dates.start
        // EventKit stretches an all-day end to cover the whole last day.
        event.endDate = dates.end
        event.notes = request.combinedNotes
        event.url = request.url

        if let alert = request.alert {
            event.addAlarm(EKAlarm(relativeOffset: -alert.secondsBeforeStart))
        }

        // Calendar keeps count-based ends natively, unlike Reminders.
        if let recurrence = request.recurrence,
           let rule = EventKitRecurrenceRuleMapper.rule(for: recurrence) {
            event.addRecurrenceRule(rule)
        }
    }

}

enum CalendarEventMappingError: LocalizedError, Equatable {
    case invalidDates
    case invalidAlert

    var errorDescription: String? {
        switch self {
        case .invalidDates: "The event's start or end time isn't a valid date."
        case .invalidAlert: "Add a time to set an event alert."
        }
    }
}
