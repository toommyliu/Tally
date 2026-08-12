import EventKit

/// Converts Tally's reminder creation values into their EventKit representation.
enum ReminderEventKitMapper {
    static func populate(
        _ reminder: EKReminder,
        from request: ReminderCreationRequest,
        calendar: EKCalendar
    ) {
        reminder.title = request.title
        reminder.calendar = calendar
        reminder.priority = request.priority
        reminder.dueDateComponents = request.dueDate
        reminder.notes = request.combinedNotes

        if let recurrence = request.recurrence,
           let rule = recurrenceRule(
                for: recurrence,
                startingAt: request.dueDate
           ) {
            reminder.addRecurrenceRule(rule)
        }
    }

    static func recurrenceRule(
        for recurrence: ReminderRecurrence,
        startingAt startDate: DateComponents? = nil
    ) -> EKRecurrenceRule? {
        guard ReminderRecurrence.supports(interval: recurrence.interval) else {
            return nil
        }

        let weekdays = recurrence.weekdays.map {
            EKRecurrenceDayOfWeek(dayOfTheWeek: eventKitWeekday(for: $0), weekNumber: 0)
        }
        let end: EKRecurrenceEnd?

        if recurrence.end != nil {
            guard let mappedEnd = recurrenceEnd(
                for: recurrence.end,
                recurrence: recurrence,
                startingAt: startDate
            ) else {
                return nil
            }

            end = mappedEnd
        } else {
            end = nil
        }

        return EKRecurrenceRule(
            recurrenceWith: eventKitFrequency(for: recurrence.frequency),
            interval: recurrence.interval,
            daysOfTheWeek: weekdays.isEmpty ? nil : weekdays,
            daysOfTheMonth: nil,
            monthsOfTheYear: nil,
            weeksOfTheYear: nil,
            daysOfTheYear: nil,
            setPositions: nil,
            end: end
        )
    }

    private static func recurrenceEnd(
        for recurrenceEnd: ReminderRecurrenceEnd?,
        recurrence: ReminderRecurrence,
        startingAt startDate: DateComponents?
    ) -> EKRecurrenceEnd? {
        switch recurrenceEnd {
        case let .date(components):
            guard let endOfDay = inclusiveEndDate(for: components) else {
                return nil
            }

            return EKRecurrenceEnd(end: endOfDay)
        case let .occurrenceCount(count) where count > 0:
            // Reminders drops count-based ends, so persist the equivalent final date instead.
            if let startDate {
                guard let endOfDay = ReminderRecurrenceCalculator.finalOccurrenceEndDate(
                    startingAt: startDate,
                    recurrence: recurrence,
                    occurrenceCount: count
                ) else {
                    return nil
                }

                return EKRecurrenceEnd(end: endOfDay)
            }

            return EKRecurrenceEnd(occurrenceCount: count)
        case .occurrenceCount, nil:
            return nil
        }
    }

    private static func inclusiveEndDate(for components: DateComponents) -> Date? {
        var calendar = components.calendar ?? .current
        if let timeZone = components.timeZone {
            calendar.timeZone = timeZone
        }

        guard let date = calendar.date(from: components) else {
            return nil
        }

        return inclusiveEndDate(for: date, calendar: calendar)
    }

    private static func inclusiveEndDate(for date: Date, calendar: Calendar) -> Date? {
        calendar.date(bySettingHour: 23, minute: 59, second: 59, of: date)
    }

    private static func eventKitFrequency(
        for frequency: ReminderRecurrence.Frequency
    ) -> EKRecurrenceFrequency {
        switch frequency {
        case .daily:
            return .daily
        case .weekly:
            return .weekly
        case .monthly:
            return .monthly
        case .yearly:
            return .yearly
        }
    }

    private static func eventKitWeekday(for weekday: ReminderWeekday) -> EKWeekday {
        switch weekday {
        case .sunday:
            return .sunday
        case .monday:
            return .monday
        case .tuesday:
            return .tuesday
        case .wednesday:
            return .wednesday
        case .thursday:
            return .thursday
        case .friday:
            return .friday
        case .saturday:
            return .saturday
        }
    }
}
