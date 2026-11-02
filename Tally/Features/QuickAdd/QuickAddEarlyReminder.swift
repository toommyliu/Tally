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
