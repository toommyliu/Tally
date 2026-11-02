import Foundation

struct CalendarEventAlert: Equatable {
    let secondsBeforeStart: TimeInterval

    init?(offset: ReminderEarlyReminder) {
        let seconds: TimeInterval
        switch offset.unit {
        case .minutes: seconds = 60
        case .hours: seconds = 3_600
        case .days: seconds = 86_400
        case .weeks: seconds = 604_800
        case .months: return nil
        }
        secondsBeforeStart = TimeInterval(offset.amount.value) * seconds
    }
}
