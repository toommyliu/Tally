import Foundation

/// Resolves occurrence-count recurrence ends to the date of their final occurrence.
enum ReminderRecurrenceCalculator {
    /// Resolves the inclusive final day EventKit needs for a finite recurrence.
    static func finalOccurrenceEndDate(
        startingAt startComponents: DateComponents,
        recurrence: ReminderRecurrence,
        occurrenceCount: Int
    ) -> Date? {
        var calendar = startComponents.calendar ?? .current
        if let timeZone = startComponents.timeZone {
            calendar.timeZone = timeZone
        }

        guard let finalOccurrence = finalOccurrenceDate(
            startingAt: startComponents,
            recurrence: recurrence,
            occurrenceCount: occurrenceCount
        ) else {
            return nil
        }

        return calendar.date(
            bySettingHour: 23,
            minute: 59,
            second: 59,
            of: finalOccurrence
        )
    }

    static func finalOccurrenceDate(
        startingAt startComponents: DateComponents,
        recurrence: ReminderRecurrence,
        occurrenceCount: Int
    ) -> Date? {
        guard (1...ReminderRecurrenceEnd.maximumOccurrenceCount).contains(occurrenceCount) else {
            return nil
        }

        var calendar = startComponents.calendar ?? .current
        if let timeZone = startComponents.timeZone {
            calendar.timeZone = timeZone
        }

        guard let startDate = calendar.date(from: startComponents) else {
            return nil
        }

        let remainingOccurrences = occurrenceCount - 1
        guard remainingOccurrences > 0 else {
            return startDate
        }

        switch recurrence.frequency {
        case .daily:
            return offsetDate(
                startDate,
                component: .day,
                interval: recurrence.interval,
                occurrenceOffset: remainingOccurrences,
                calendar: calendar
            )
        case .weekly:
            return weeklyOccurrenceDate(
                startingAt: startDate,
                recurrence: recurrence,
                remainingOccurrences: remainingOccurrences,
                calendar: calendar
            )
        case .monthly:
            return calendarUnitOccurrenceDate(
                startingAt: startDate,
                component: .month,
                interval: recurrence.interval,
                remainingOccurrences: remainingOccurrences,
                calendar: calendar
            )
        case .yearly:
            return calendarUnitOccurrenceDate(
                startingAt: startDate,
                component: .year,
                interval: recurrence.interval,
                remainingOccurrences: remainingOccurrences,
                calendar: calendar
            )
        }
    }

    private static func weeklyOccurrenceDate(
        startingAt startDate: Date,
        recurrence: ReminderRecurrence,
        remainingOccurrences: Int,
        calendar: Calendar
    ) -> Date? {
        let weekdays = Set(recurrence.weekdays.map(\.rawValue))

        if weekdays.count <= 1 {
            return offsetDate(
                startDate,
                component: .weekOfYear,
                interval: recurrence.interval,
                occurrenceOffset: remainingOccurrences,
                calendar: calendar
            )
        }

        guard let initialWeek = calendar.dateInterval(of: .weekOfYear, for: startDate)?.start else {
            return nil
        }

        var candidate = startDate
        var remaining = remainingOccurrences

        while remaining > 0 {
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: candidate),
                  let candidateWeek = calendar.dateInterval(of: .weekOfYear, for: nextDay)?.start,
                  let weekDistance = calendar.dateComponents(
                    [.day],
                    from: initialWeek,
                    to: candidateWeek
                  ).day else {
                return nil
            }

            candidate = nextDay
            let activeWeek = (weekDistance / 7).isMultiple(of: recurrence.interval)
            let weekday = calendar.component(.weekday, from: candidate)

            if activeWeek, weekdays.contains(weekday) {
                remaining -= 1
            }
        }

        return candidate
    }

    /// Advances by whole calendar units and skips invalid dates, matching recurrence behavior.
    private static func calendarUnitOccurrenceDate(
        startingAt startDate: Date,
        component: Calendar.Component,
        interval: Int,
        remainingOccurrences: Int,
        calendar: Calendar
    ) -> Date? {
        let preserved = calendar.dateComponents(
            [.timeZone, .month, .day, .hour, .minute, .second, .nanosecond],
            from: startDate
        )

        if advancesWithoutInvalidDates(component: component, components: preserved) {
            return offsetDate(
                startDate,
                component: component,
                interval: interval,
                occurrenceOffset: remainingOccurrences,
                calendar: calendar
            )
        }

        let anchorComponents = calendar.dateComponents([.year, .month], from: startDate)
        var monthAnchor = anchorComponents
        monthAnchor.calendar = calendar
        monthAnchor.timeZone = calendar.timeZone
        monthAnchor.day = 1

        guard let anchorDate = calendar.date(from: monthAnchor) else {
            return nil
        }

        var remaining = remainingOccurrences
        var cycle = 1
        let maximumCycles = ReminderRecurrenceEnd.maximumOccurrenceCount * 10

        while remaining > 0, cycle <= maximumCycles {
            let multiplication = interval.multipliedReportingOverflow(by: cycle)
            guard !multiplication.overflow,
                  let unitDate = calendar.date(
                    byAdding: component,
                    value: multiplication.partialValue,
                    to: anchorDate
                  ) else {
                return nil
            }

            let unitComponents = calendar.dateComponents([.year, .month], from: unitDate)
            var candidateComponents = preserved
            candidateComponents.calendar = calendar
            candidateComponents.timeZone = calendar.timeZone
            candidateComponents.year = unitComponents.year
            candidateComponents.month = component == .year ? preserved.month : unitComponents.month

            if let candidate = calendar.date(from: candidateComponents),
               calendar.component(.year, from: candidate) == candidateComponents.year,
               calendar.component(.month, from: candidate) == candidateComponents.month,
               calendar.component(.day, from: candidate) == preserved.day {
                remaining -= 1

                if remaining == 0 {
                    return candidate
                }
            }

            cycle += 1
        }

        return nil
    }

    /// Most dates can jump directly; only leap days and late-month dates need cycle-by-cycle skips.
    private static func advancesWithoutInvalidDates(
        component: Calendar.Component,
        components: DateComponents
    ) -> Bool {
        switch component {
        case .year:
            return components.month != 2 || components.day != 29
        case .month:
            return (components.day ?? 32) <= 28
        default:
            return false
        }
    }

    private static func offsetDate(
        _ startDate: Date,
        component: Calendar.Component,
        interval: Int,
        occurrenceOffset: Int,
        calendar: Calendar
    ) -> Date? {
        let multiplication = interval.multipliedReportingOverflow(by: occurrenceOffset)
        guard !multiplication.overflow else {
            return nil
        }

        return calendar.date(
            byAdding: component,
            value: multiplication.partialValue,
            to: startDate
        )
    }
}
