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
        guard let startDate = date(from: request.timing.start, in: dateCalendar, isAllDay: isAllDay),
              let endDate = date(from: request.timing.end, in: dateCalendar, isAllDay: isAllDay) else {
            throw CalendarEventMappingError.invalidDates
        }

        event.title = request.title
        event.calendar = calendar
        event.isAllDay = isAllDay
        // All-day events float with the viewer; timed events keep the zone they were typed in.
        event.timeZone = isAllDay ? nil : request.timing.start.timeZone ?? dateCalendar.timeZone
        event.startDate = startDate
        // EventKit stretches an all-day end to cover the whole last day.
        event.endDate = endDate
        event.notes = request.combinedNotes
        event.url = request.url

        if let alert = request.alert {
            event.addAlarm(EKAlarm(relativeOffset: -offset(for: alert)))
        }

        // Calendar keeps count-based ends natively, unlike Reminders.
        if let recurrence = request.recurrence,
           let rule = EventKitRecurrenceRuleMapper.rule(for: recurrence) {
            event.addRecurrenceRule(rule)
        }
    }

    static func offset(for alert: ReminderEarlyReminder) -> TimeInterval {
        let minutes: Int
        switch alert.unit {
        case .minutes:
            minutes = alert.amount
        case .hours:
            minutes = alert.amount * 60
        case .days:
            minutes = alert.amount * 60 * 24
        case .weeks:
            minutes = alert.amount * 60 * 24 * 7
        }

        return TimeInterval(minutes * 60)
    }

    /// EventKit reads floating all-day dates in the system time zone, so the
    /// day is placed there regardless of the zone it was parsed in.
    private static func date(
        from components: DateComponents,
        in calendar: Calendar,
        isAllDay: Bool
    ) -> Date? {
        var calendar = components.calendar ?? calendar

        if isAllDay {
            calendar.timeZone = .current
            return calendar.date(from: DateComponents(
                year: components.year,
                month: components.month,
                day: components.day
            ))
        }

        if let timeZone = components.timeZone {
            calendar.timeZone = timeZone
        }

        return calendar.date(from: components)
    }
}

enum CalendarEventMappingError: LocalizedError {
    case invalidDates

    var errorDescription: String? {
        "The event's start or end time isn't a valid date."
    }
}
