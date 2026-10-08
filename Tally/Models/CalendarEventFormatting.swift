import Foundation

extension CalendarEventTiming {
    /// `Tomorrow 3:00 PM – 4:00 PM`, `Today · All day`, or `Oct 3 – Oct 5`.
    var shortDisplayTitle: String {
        let startTitle = start.shortDisplayTitle

        if isAllDay {
            return dayCount > 1
                ? "\(startTitle) – \(end.shortDisplayTitle)"
                : "\(startTitle) · All day"
        }

        let calendar = Calendar.current
        guard let startDate = calendar.date(from: start),
              let endDate = calendar.date(from: end) else {
            return startTitle
        }

        // An end at the following midnight still reads as the same evening.
        let endsSameDay = calendar.isDate(startDate, inSameDayAs: endDate.addingTimeInterval(-1))
        let endTitle = endsSameDay
            ? endDate.formatted(.dateTime.hour(.defaultDigits(amPM: .abbreviated)).minute(.twoDigits))
            : end.shortDisplayTitle
        return "\(startTitle) – \(endTitle)"
    }

    /// `45 min`, `1 hr 30 min`, `All day`, or `3 days`.
    var lengthDisplayTitle: String {
        if isAllDay {
            return dayCount > 1 ? "\(dayCount) days" : "All day"
        }

        guard let minutes = durationMinutes else {
            return "Length"
        }

        return Self.lengthTitle(minutes: minutes)
    }

    /// The duration-menu option matching this timing, if any.
    var selectedLength: QuickAddEventLength? {
        if isAllDay {
            return dayCount == 1 ? .allDay : nil
        }

        return durationMinutes.map { .duration(.minutes($0)) }
    }

    var dayCount: Int {
        let calendar = Calendar.current
        guard let startDate = calendar.date(from: start),
              let endDate = calendar.date(from: end) else {
            return 1
        }

        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: startDate),
            to: calendar.startOfDay(for: endDate)
        ).day ?? 0
        return max(days + 1, 1)
    }

    static func lengthTitle(minutes: Int) -> String {
        let days = minutes / (24 * 60)
        if days > 0, minutes % (24 * 60) == 0 {
            return days == 1 ? "1 day" : "\(days) days"
        }

        let hours = minutes / 60
        let remainder = minutes % 60
        switch (hours, remainder) {
        case (0, _):
            return "\(remainder) min"
        case (_, 0):
            return "\(hours) hr"
        default:
            return "\(hours) hr \(remainder) min"
        }
    }
}

extension QuickAddEventLength {
    /// The length in minutes for timed options, `nil` for all-day and day lengths.
    var minutes: Int? {
        guard case let .duration(duration) = self, duration.unit == .minutes else {
            return nil
        }

        return duration.amount
    }

    var displayTitle: String {
        switch self {
        case .allDay:
            return "All day"
        case let .duration(duration):
            switch duration.unit {
            case .minutes:
                return CalendarEventTiming.lengthTitle(minutes: duration.amount)
            case .days:
                return duration.amount == 1 ? "1 day" : "\(duration.amount) days"
            }
        }
    }
}
