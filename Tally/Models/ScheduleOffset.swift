import Foundation

enum ScheduleUnit: CaseIterable, Hashable {
    case minutes, hours, days, weeks, months

    var calendarComponent: Calendar.Component {
        switch self {
        case .minutes: .minute
        case .hours: .hour
        case .days: .day
        case .weeks: .weekOfYear
        case .months: .month
        }
    }

    var requiresReminderTime: Bool { self == .minutes || self == .hours }
}

struct EarlyReminderAmount: Hashable {
    static let allowedValues = 1...99
    let value: Int

    init?(validating value: Int) {
        guard Self.allowedValues.contains(value) else { return nil }
        self.value = value
    }

    static func parseDigits(_ text: String) -> EarlyReminderAmountInput {
        guard !text.isEmpty, text.utf8.allSatisfy({ (48...57).contains($0) }) else {
            return .notWholeNumber
        }
        let significant = text.drop { $0 == "0" }
        guard !significant.isEmpty else { return .belowMinimum }
        guard significant.count <= 2 else { return .aboveMaximum }
        guard let value = Int(significant), let amount = Self(validating: value) else { return .aboveMaximum }
        return .valid(amount)
    }
}

enum EarlyReminderAmountInput {
    case valid(EarlyReminderAmount)
    case belowMinimum
    case aboveMaximum
    case notWholeNumber
}

struct ReminderEarlyReminder: Hashable {
    let amount: EarlyReminderAmount
    let unit: ScheduleUnit
}
