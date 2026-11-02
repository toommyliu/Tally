import Foundation

struct QuickAddParseContext {
    let calendar: Calendar
    let now: Date
}

enum EarlyReminderFirePoint: Equatable {
    case instant(Date, timeZone: TimeZone)
    case day(DateComponents)
}

enum EarlyOffsetSyntax: Equatable {
    case offset(ReminderEarlyReminder)
    case tooLarge(digits: String, unit: ScheduleUnit)
    case tooSmall(unit: ScheduleUnit)
}

struct EarlyReminderClause: Equatable {
    let value: EarlyOffsetSyntax
    let range: NSRange
}

struct QuickAddEarlyReminder: Equatable {
    enum State: Equatable {
        case reminder(ReminderEarlyReminder, firePoint: EarlyReminderFirePoint)
        case event(ReminderEarlyReminder, alarm: CalendarEventAlert, firePoint: EarlyReminderFirePoint)
        case needsDate(ReminderEarlyReminder)
        case needsTime(ReminderEarlyReminder)
        case tooLarge(digits: String, unit: ScheduleUnit)
        case tooSmall(unit: ScheduleUnit)
        case unsupportedEventMonths(ReminderEarlyReminder)
        case cannotResolveDate(ReminderEarlyReminder)
    }

    let range: NSRange
    let state: State

    fileprivate init(range: NSRange, state: State) {
        self.range = range
        self.state = state
    }

    var token: QuickAddToken { QuickAddToken(kind: .earlyReminder, range: range) }
    var isWarning: Bool { warning != nil }
    var reminderValue: ReminderEarlyReminder? {
        guard case let .reminder(offset, _) = state else { return nil }
        return offset
    }
    var eventValue: CalendarEventAlert? {
        guard case let .event(_, alarm, _) = state else { return nil }
        return alarm
    }
    var selectedOffset: ReminderEarlyReminder? {
        switch state {
        case let .reminder(offset, _), let .event(offset, _, _), let .needsDate(offset),
             let .needsTime(offset), let .unsupportedEventMonths(offset), let .cannotResolveDate(offset): offset
        case .tooLarge, .tooSmall: nil
        }
    }
    var firePoint: EarlyReminderFirePoint? {
        switch state {
        case let .reminder(_, point), let .event(_, _, point): point
        default: nil
        }
    }
    var warning: String? {
        switch state {
        case .reminder, .event: nil
        case .needsDate: "Add a date"
        case .needsTime: "Add a time"
        case .tooLarge: "Up to 99"
        case .tooSmall: "Use 1 or more"
        case .unsupportedEventMonths: "Use days or weeks"
        case .cannotResolveDate: "Choose another date"
        }
    }
}

enum EarlyReminderTarget {
    case reminder(dueDate: DateComponents?)
    case event(timing: CalendarEventTiming?)

    func preview(_ offset: ReminderEarlyReminder, context: QuickAddParseContext) -> QuickAddEarlyReminder {
        EarlyReminderResolver.resolve(
            EarlyReminderClause(value: .offset(offset), range: NSRange(location: 0, length: 0)),
            target: self, context: context
        )
    }

    var hasTime: Bool {
        switch self {
        case let .reminder(dueDate): dueDate?.hour != nil
        case let .event(timing): timing.map { !$0.isAllDay } ?? false
        }
    }
    var isEvent: Bool {
        if case .event = self { true } else { false }
    }
}

enum EarlyReminderResolver {
    static func resolve(_ clause: EarlyReminderClause, target: EarlyReminderTarget,
                        context: QuickAddParseContext) -> QuickAddEarlyReminder {
        let state: QuickAddEarlyReminder.State
        switch clause.value {
        case let .tooLarge(digits, unit): state = .tooLarge(digits: digits, unit: unit)
        case let .tooSmall(unit): state = .tooSmall(unit: unit)
        case let .offset(offset): state = resolve(offset, target: target, calendar: context.calendar)
        }
        return QuickAddEarlyReminder(range: clause.range, state: state)
    }

    private static func resolve(_ offset: ReminderEarlyReminder, target: EarlyReminderTarget,
                                calendar: Calendar) -> QuickAddEarlyReminder.State {
        switch target {
        case let .reminder(dueDate):
            guard var due = dueDate else { return .needsDate(offset) }
            guard due.hour != nil || !offset.unit.requiresReminderTime else { return .needsTime(offset) }
            var effective = due.calendar ?? calendar
            effective.timeZone = due.timeZone ?? effective.timeZone
            let dateOnly = due.hour == nil
            due.calendar = effective
            due.timeZone = effective.timeZone
            if dateOnly { due.hour = 12; due.minute = 0 }
            guard let date = effective.date(from: due),
                  effective.component(.year, from: date) == due.year,
                  effective.component(.month, from: date) == due.month,
                  effective.component(.day, from: date) == due.day,
                  effective.component(.hour, from: date) == due.hour,
                  effective.component(.minute, from: date) == (due.minute ?? 0),
                  let fire = effective.date(byAdding: offset.unit.calendarComponent, value: -offset.amount.value, to: date)
            else { return .cannotResolveDate(offset) }
            let point: EarlyReminderFirePoint = dateOnly
                ? .day(effective.dateComponents([.calendar, .timeZone, .year, .month, .day], from: fire))
                : .instant(fire, timeZone: effective.timeZone)
            return .reminder(offset, firePoint: point)
        case let .event(timing):
            guard let timing else { return .needsDate(offset) }
            guard !timing.isAllDay else { return .needsTime(offset) }
            guard let alarm = CalendarEventAlert(offset: offset) else { return .unsupportedEventMonths(offset) }
            guard let dates = timing.eventKitDates(in: calendar) else { return .cannotResolveDate(offset) }
            return .event(offset, alarm: alarm, firePoint: .instant(
                dates.start.addingTimeInterval(-alarm.secondsBeforeStart),
                timeZone: timing.start.timeZone ?? timing.start.calendar?.timeZone ?? calendar.timeZone
            ))
        }
    }
}

enum EarlyReminderMenuSchedule { case dateOnly, timed }

struct EarlyReminderPreset: Identifiable, Hashable {
    let id: ReminderEarlyReminder
    var title: String { EarlyReminderCatalog.fullTitle(for: id) }
    var syntax: String { EarlyReminderCatalog.token(for: id) }
}

enum EarlyReminderCatalog {
    private struct Row {
        let offset: ReminderEarlyReminder
        let dateOrder: Int?
        let timedOrder: Int?
        init(_ amount: Int, _ unit: ScheduleUnit, _ dateOrder: Int?, _ timedOrder: Int?) {
            offset = ReminderEarlyReminder(amount: EarlyReminderAmount(validating: amount)!, unit: unit)
            self.dateOrder = dateOrder
            self.timedOrder = timedOrder
        }
    }
    private static let rows = [
        Row(5, .minutes, nil, 0), Row(15, .minutes, nil, 1), Row(30, .minutes, nil, 2),
        Row(1, .hours, nil, 3), Row(2, .hours, nil, 4), Row(1, .days, 0, 5),
        Row(2, .days, 1, 6), Row(1, .weeks, 2, 7), Row(2, .weeks, 3, nil),
        Row(1, .months, 4, 8), Row(3, .months, 5, nil), Row(6, .months, 6, nil)
    ]
    static func presets(for schedule: EarlyReminderMenuSchedule) -> [EarlyReminderPreset] {
        rows.compactMap { row -> (Int, ReminderEarlyReminder)? in
            let order = schedule == .timed ? row.timedOrder : row.dateOrder
            return order.map { ($0, row.offset) }
        }.sorted { $0.0 < $1.0 }.map { EarlyReminderPreset(id: $0.1) }
    }
    static func token(for offset: ReminderEarlyReminder) -> String {
        let suffix: String = switch offset.unit {
        case .minutes: "m"
        case .hours: "h"
        case .days: "d"
        case .weeks: "w"
        case .months: "mo"
        }
        return "!\(offset.amount.value)\(suffix)"
    }
    static func unitTitle(_ unit: ScheduleUnit) -> String {
        switch unit {
        case .minutes: "minute"
        case .hours: "hour"
        case .days: "day"
        case .weeks: "week"
        case .months: "month"
        }
    }
    static func fullTitle(for offset: ReminderEarlyReminder) -> String {
        let count = offset.amount.value
        return "\(count) \(unitTitle(offset.unit))\(count == 1 ? "" : "s") before"
    }
    static func compactTitle(for offset: ReminderEarlyReminder) -> String {
        switch offset.unit {
        case .minutes: "\(offset.amount.value) min before"
        case .hours: "\(offset.amount.value) hr before"
        default: fullTitle(for: offset)
        }
    }
}

struct EarlyReminderPresentation {
    let chipTitle: String
    let previewTitle: String
    let accessibilityValue: String
    let detail: String?
    let showsWarning: Bool

    init(_ parsed: QuickAddEarlyReminder?, calendar: Calendar, locale: Locale) {
        showsWarning = parsed?.isWarning ?? false
        if let warning = parsed?.warning {
            previewTitle = warning
            chipTitle = warning
            accessibilityValue = warning
            detail = switch parsed?.state {
            case .unsupportedEventMonths: "Calendar event alerts cannot repeat a calendar-month offset. Use days or weeks."
            case .needsDate: "Add a date to set an early reminder."
            case .needsTime: "Add a time to use this offset."
            case .tooLarge: "Use an amount up to 99."
            case .tooSmall: "Use an amount of 1 or more."
            default: "Choose another date."
            }
            return
        }
        guard let offset = parsed?.selectedOffset, let point = parsed?.firePoint else {
            previewTitle = ""
            chipTitle = "Early reminder"
            accessibilityValue = "None"
            detail = nil
            return
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        let short: String
        let full: String
        switch point {
        case let .instant(date, timeZone):
            formatter.timeZone = timeZone
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            short = formatter.string(from: date).replacingOccurrences(of: " ", with: " ").replacingOccurrences(of: " ", with: " ")
            formatter.dateFormat = "EEE, MMM d"
            previewTitle = "\(formatter.string(from: date)) at \(short)"
            formatter.dateFormat = nil
            formatter.dateStyle = .full
            formatter.timeStyle = .short
            full = formatter.string(from: date)
        case let .day(components):
            formatter.calendar = components.calendar ?? calendar
            formatter.timeZone = components.timeZone ?? calendar.timeZone
            let date = formatter.calendar.date(from: components)!
            formatter.dateFormat = "EEE"
            short = formatter.string(from: date)
            formatter.dateFormat = "EEE, MMM d"
            previewTitle = formatter.string(from: date)
            formatter.dateFormat = nil
            formatter.dateStyle = .full
            formatter.timeStyle = .none
            full = formatter.string(from: date)
        }
        chipTitle = "\(EarlyReminderCatalog.compactTitle(for: offset)) · \(short)"
        accessibilityValue = "\(EarlyReminderCatalog.fullTitle(for: offset)) · \(full)"
        detail = accessibilityValue
    }
}

struct EarlyReminderCustomInput {
    var amountText: String
    var unit: ScheduleUnit

    var offset: ReminderEarlyReminder? {
        guard case let .valid(amount) = EarlyReminderAmount.parseDigits(amountText) else { return nil }
        return ReminderEarlyReminder(amount: amount, unit: unit)
    }
    func unitMenuTitle(_ unit: ScheduleUnit) -> String {
        "\(EarlyReminderCatalog.unitTitle(unit))\(offset?.amount.value == 1 ? "" : "s") before"
    }

    var numericWarning: String? {
        switch EarlyReminderAmount.parseDigits(amountText) {
        case .valid: nil
        case .belowMinimum: "Use 1 or more"
        case .aboveMaximum: "Up to 99"
        case .notWholeNumber: "Use a whole number"
        }
    }
}
