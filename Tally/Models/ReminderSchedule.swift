import Foundation

/// A value representation of a reminder recurrence, independent of EventKit.
struct ReminderRecurrence: Equatable {
    /// EventKit stores recurrence intervals as signed 32-bit values internally.
    static let maximumInterval = Int(Int32.max)

    enum Frequency: Equatable {
        case daily
        case weekly
        case monthly
        case yearly
    }

    let frequency: Frequency
    let interval: Int
    let weekdays: [ReminderWeekday]
    let end: ReminderRecurrenceEnd?

    init(
        frequency: Frequency,
        interval: Int = 1,
        weekdays: [ReminderWeekday] = [],
        end: ReminderRecurrenceEnd? = nil
    ) {
        self.frequency = frequency
        self.interval = max(interval, 1)
        self.weekdays = weekdays
        self.end = end
    }

    static func supports(interval: Int) -> Bool {
        (1...maximumInterval).contains(interval)
    }
}

/// A recurrence endpoint represented by either a local calendar date or occurrence count.
enum ReminderRecurrenceEnd: Equatable {
    static let maximumOccurrenceCount = 10_000

    case date(DateComponents)
    case occurrenceCount(Int)
}

/// A relative alert shown before a reminder's timed due date.
struct ReminderEarlyReminder: Equatable {
    enum Unit: Equatable {
        case minutes
        case hours
        case days
        case weeks
    }

    let amount: Int
    let unit: Unit

    init(amount: Int, unit: Unit) {
        self.amount = max(amount, 1)
        self.unit = unit
    }
}

/// Weekday values use Foundation's Sunday-first numbering for direct calendar conversion.
enum ReminderWeekday: Int, CaseIterable, Equatable {
    case sunday = 1
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday
}
