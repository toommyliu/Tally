import Foundation

struct QuickAddFields: Equatable {
    var title: String
    var listName: String?
    var tags: [String]
    var inlineNotes: String?
    var dueDate: DateComponents?
    var recurrence: ReminderRecurrence?
    var earlyReminder: ReminderEarlyReminder?
    var url: URL?
    var priority: Int
    var usedTokens: [QuickAddToken]
}

struct QuickAddToken: Equatable {
    enum Kind: Equatable {
        case list
        case tag
        case date
        case time
        case recurrence
        case earlyReminder
        case url
        case priority
        case note
    }

    enum Source: Equatable {
        case explicit
        case inferred
    }

    var kind: Kind
    var range: NSRange
    var source: Source

    init(kind: Kind, range: NSRange, source: Source = .explicit) {
        self.kind = kind
        self.range = range
        self.source = source
    }
}

struct QuickAddSuppressedToken: Equatable {
    var kind: QuickAddToken.Kind
    var range: NSRange
    var text: String
}

enum QuickAddListTokenCodec {
    private static let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))

    static func encode(_ listTitle: String) -> String {
        listTitle.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? listTitle
    }

    static func decode(_ listToken: String) -> String {
        listToken.removingPercentEncoding ?? listToken
    }
}

enum QuickAddParser {
    static func parse(
        _ input: String,
        calendar: Calendar = .current,
        now: Date = Date(),
        suppressedTokens: [QuickAddSuppressedToken] = []
    ) -> QuickAddFields {
        var titleTokens: [String] = []
        var listName: String?
        var tags: [String] = []
        var inlineNotes: String?
        var dueDate: DateComponents?
        var recurrence: ReminderRecurrence?
        var earlyReminder: ReminderEarlyReminder?
        var acceptedEarlyReminderRange: NSRange?
        var url: URL?
        var priority = 0
        var usedTokens: [QuickAddToken] = []
        var detachedRecurrenceTokens: [QuickAddRecurrenceTokenMatch] = []
        var detachedScheduleTokens: [ScheduleTokenMatch] = []
        let tokens = QuickAddParsingSupport.scanTokens(in: input)
        let reminderMetadata = QuickAddReminderMetadataParser.parse(
            tokens: tokens,
            calendar: calendar,
            now: now
        )
        var index = 0

        while index < tokens.count {
            let token = tokens[index]

            if isInsideSuppressedToken(token, in: input, suppressedTokens: suppressedTokens) {
                titleTokens.append(token.text)
                index += 1
                continue
            }

            if tokenStartsInlineNotes(token) {
                inlineNotes = noteText(from: token, in: input)
                usedTokens.append(QuickAddToken(kind: .note, range: noteRange(from: token, in: input)))
                break
            }

            if let match = reminderMetadata.invalidRecurrences.first(where: {
                $0.startIndex == index
            }) {
                titleTokens.append(contentsOf: tokens[index...match.endIndex].map(\.text))
                index = match.endIndex + 1
                continue
            }

            if dueDate == nil,
               recurrence == nil,
               let match = reminderMetadata.recurrences.first(where: {
                   $0.startIndex == index
               }) {
                let suppressedDetachedTokens = match.detachedTokens.filter {
                    isInsideSuppressedToken(
                        tokens[$0.startIndex],
                        in: input,
                        suppressedTokens: suppressedTokens
                    )
                }
                dueDate = suppressedDetachedTokens.contains(where: \.includesTime)
                    ? match.dueDateWithoutTime
                    : match.dueDate
                if suppressedDetachedTokens.contains(where: \.includesEnd) {
                    recurrence = ReminderRecurrence(
                        frequency: match.recurrence.frequency,
                        interval: match.recurrence.interval,
                        weekdays: match.recurrence.weekdays
                    )
                } else {
                    recurrence = match.recurrence
                }
                detachedRecurrenceTokens = match.detachedTokens.filter { token in
                    !suppressedDetachedTokens.contains(where: { $0.range == token.range })
                }
                usedTokens.append(QuickAddToken(kind: .recurrence, range: match.range))
                index = match.endIndex + 1
                continue
            }

            if let match = detachedRecurrenceTokens.first(where: { $0.startIndex == index }) {
                usedTokens.append(QuickAddToken(kind: .recurrence, range: match.range))
                index = match.endIndex + 1
                continue
            }

            if let match = detachedScheduleTokens.first(where: { $0.startIndex == index }) {
                usedTokens.append(match.token)
                index = match.endIndex + 1
                continue
            }

            if let match = reminderMetadata.earlyReminders.first(where: {
                $0.startIndex == index
            }) {
                if earlyReminder == nil {
                    earlyReminder = match.earlyReminder
                    acceptedEarlyReminderRange = match.range
                    usedTokens.append(QuickAddToken(kind: .earlyReminder, range: match.range))
                } else {
                    titleTokens.append(contentsOf: tokens[index...match.endIndex].map(\.text))
                }

                index = match.endIndex + 1
                continue
            }

            if url == nil,
               let match = reminderMetadata.urls.first(where: {
                   $0.index == index
               }) {
                url = match.url
                usedTokens.append(QuickAddToken(kind: .url, range: match.range))
                index += 1
                continue
            }

            if let encodedListName = QuickAddParsingSupport.prefixedMetadataValue(
                "#",
                in: token.text
            ) {
                listName = QuickAddListTokenCodec.decode(encodedListName)
                usedTokens.append(QuickAddToken(kind: .list, range: token.range))
                index += 1
                continue
            }

            if QuickAddParsingSupport.trimmingSentencePunctuation(from: token.text) == "@" {
                usedTokens.append(QuickAddToken(kind: .tag, range: token.range))
                index += 1
                continue
            }

            if let tag = QuickAddParsingSupport.prefixedMetadataValue("@", in: token.text) {
                tags.append(tag)
                usedTokens.append(QuickAddToken(kind: .tag, range: token.range))
                index += 1
                continue
            }

            if let parsedPriority = QuickAddParsingSupport.priority(for: token.text) {
                priority = parsedPriority
                usedTokens.append(QuickAddToken(kind: .priority, range: token.range))
                index += 1
                continue
            }

            if dueDate == nil,
               !isInsideUnmatchedRecurrenceEndDate(
                   at: index,
                   in: tokens,
                   calendar: calendar,
                   now: now
               ),
               let parsedSchedule = parseScheduleExpression(
                at: index,
                in: tokens,
                metadata: reminderMetadata,
                calendar: calendar,
                now: now
               ) {
                let suppressedDetachedTokens = parsedSchedule.detachedTokens.filter {
                    isInsideSuppressedToken(
                        tokens[$0.startIndex],
                        in: input,
                        suppressedTokens: suppressedTokens
                    )
                }
                dueDate = suppressedDetachedTokens.isEmpty
                    ? parsedSchedule.components
                    : parsedSchedule.componentsWithoutDetachedTime ?? parsedSchedule.components
                usedTokens.append(QuickAddToken(
                    kind: parsedSchedule.kind,
                    range: parsedSchedule.range,
                    source: parsedSchedule.source
                ))
                detachedScheduleTokens = parsedSchedule.detachedTokens
                index = parsedSchedule.endIndex + 1
                continue
            }

            titleTokens.append(token.text)
            index += 1
        }

        if earlyReminder != nil,
           dueDate?.hour == nil,
           let range = acceptedEarlyReminderRange,
           NSMaxRange(range) <= (input as NSString).length {
            let suppression = QuickAddSuppressedToken(
                kind: .earlyReminder,
                range: range,
                text: (input as NSString).substring(with: range)
            )
            return parse(
                input,
                calendar: calendar,
                now: now,
                suppressedTokens: suppressedTokens + [suppression]
            )
        }

        return QuickAddFields(
            title: titleTokens.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines),
            listName: listName,
            tags: tags,
            inlineNotes: inlineNotes,
            dueDate: dueDate,
            recurrence: recurrence,
            earlyReminder: earlyReminder,
            url: url,
            priority: priority,
            usedTokens: usedTokens
        )
    }

    private struct ScheduleMatch {
        var components: DateComponents
        var kind: QuickAddToken.Kind
        var range: NSRange
        var endIndex: Int
        var source: QuickAddToken.Source
        var detachedTokens: [ScheduleTokenMatch] = []
        var componentsWithoutDetachedTime: DateComponents?
    }

    private struct ScheduleTokenMatch {
        var token: QuickAddToken
        var startIndex: Int
        var endIndex: Int
    }

    private struct BaseDateMatch {
        var components: DateComponents
        var range: NSRange
        var endIndex: Int
        var source: QuickAddToken.Source
    }

    private typealias ParsedTime = QuickAddParsedTime

    private struct RelativeDurationMatch {
        var amount: Int
        var unit: RelativeUnit
        var endIndex: Int
    }

    private static func tokenStartsInlineNotes(_ token: QuickAddScannedToken) -> Bool {
        token.text.hasPrefix("//")
    }

    private static func noteRange(from token: QuickAddScannedToken, in input: String) -> NSRange {
        let fullLength = (input as NSString).length
        return NSRange(location: token.range.location, length: fullLength - token.range.location)
    }

    private static func noteText(from token: QuickAddScannedToken, in input: String) -> String? {
        let fullText = input as NSString
        let fullLength = fullText.length
        let noteStart = token.range.location + 2

        guard noteStart <= fullLength else {
            return nil
        }

        let note = fullText
            .substring(from: noteStart)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return note.isEmpty ? nil : note
    }

    private static func isInsideSuppressedToken(
        _ token: QuickAddScannedToken,
        in input: String,
        suppressedTokens: [QuickAddSuppressedToken]
    ) -> Bool {
        let originalText = input as NSString

        return suppressedTokens.contains { suppressedToken in
            guard NSIntersectionRange(token.range, suppressedToken.range).length > 0,
                  NSMaxRange(suppressedToken.range) <= originalText.length else {
                return false
            }

            return originalText.substring(with: suppressedToken.range) == suppressedToken.text
        }
    }

    private static func isInsideUnmatchedRecurrenceEndDate(
        at index: Int,
        in tokens: [QuickAddScannedToken],
        calendar: Calendar,
        now: Date
    ) -> Bool {
        for keywordIndex in [index - 1, index - 2]
        where normalizedToken(at: keywordIndex, in: tokens) == "until" {
            guard let match = QuickAddParsingSupport.parseCalendarDate(
                at: keywordIndex + 1,
                in: tokens,
                calendar: calendar,
                relativeTo: now
            ) else {
                continue
            }

            if (keywordIndex + 1...match.endIndex).contains(index) {
                return true
            }
        }

        return false
    }

    private static func parseScheduleExpression(
        at index: Int,
        in tokens: [QuickAddScannedToken],
        metadata: QuickAddReminderMetadataMatches,
        calendar: Calendar,
        now: Date
    ) -> ScheduleMatch? {
        if let daypart = parseDaypartExpression(at: index, in: tokens, calendar: calendar, now: now) {
            return daypart
        }

        if let dateMath = parseDateMathExpression(at: index, in: tokens, calendar: calendar, now: now) {
            return dateMath
        }

        if let signedRelativeDuration = parseSignedRelativeDuration(at: index, in: tokens, calendar: calendar, now: now) {
            return signedRelativeDuration
        }

        if let relativeDate = parseRelativeDate(at: index, in: tokens, calendar: calendar, now: now) {
            var components = relativeDate.components
            let componentsWithoutTime = components
            var kind = relativeDate.kind
            var range = relativeDate.range
            var endIndex = relativeDate.endIndex

            if components.hour == nil,
               let time = followingTimeExpression(
                after: endIndex,
                in: tokens,
                metadata: metadata
               ) {
                guard let resolvedComponents = QuickAddParsingSupport.applying(
                    time.time,
                    to: components,
                    calendar: calendar
                ) else {
                    return nil
                }

                components = resolvedComponents
                kind = .time
                if time.startIndex == endIndex + 1 {
                    range = union(range, time.range)
                    endIndex = time.endIndex
                } else {
                    return ScheduleMatch(
                        components: components,
                        kind: kind,
                        range: range,
                        endIndex: endIndex,
                        source: .inferred,
                        detachedTokens: [ScheduleTokenMatch(
                            token: QuickAddToken(kind: .time, range: time.range, source: .inferred),
                            startIndex: time.startIndex,
                            endIndex: time.endIndex
                        )],
                        componentsWithoutDetachedTime: componentsWithoutTime
                    )
                }
            }

            return ScheduleMatch(
                components: components,
                kind: kind,
                range: range,
                endIndex: endIndex,
                source: .inferred
            )
        }

        if let baseDate = parseBaseDateExpression(at: index, in: tokens, calendar: calendar, now: now) {
            var components = baseDate.components
            let componentsWithoutTime = components
            var kind: QuickAddToken.Kind = .date
            var range = baseDate.range
            var endIndex = baseDate.endIndex

            if let time = followingTimeExpression(
                after: endIndex,
                in: tokens,
                metadata: metadata
            ) {
                guard let resolvedComponents = QuickAddParsingSupport.applying(
                    time.time,
                    to: components,
                    calendar: calendar
                ) else {
                    return nil
                }

                components = resolvedComponents
                kind = .time
                if time.startIndex == endIndex + 1 {
                    range = union(range, time.range)
                    endIndex = time.endIndex
                } else {
                    return ScheduleMatch(
                        components: components,
                        kind: kind,
                        range: range,
                        endIndex: endIndex,
                        source: baseDate.source,
                        detachedTokens: [ScheduleTokenMatch(
                            token: QuickAddToken(kind: .time, range: time.range, source: baseDate.source),
                            startIndex: time.startIndex,
                            endIndex: time.endIndex
                        )],
                        componentsWithoutDetachedTime: componentsWithoutTime
                    )
                }
            }

            return ScheduleMatch(
                components: components,
                kind: kind,
                range: range,
                endIndex: endIndex,
                source: baseDate.source
            )
        }

        if let time = parseTimeOnlyExpression(at: index, in: tokens, calendar: calendar, now: now) {
            return time
        }

        return nil
    }

    private static func parseBaseDateExpression(
        at index: Int,
        in tokens: [QuickAddScannedToken],
        calendar: Calendar,
        now: Date
    ) -> BaseDateMatch? {
        guard let normalized = normalizedToken(at: index, in: tokens) else {
            return nil
        }

        if normalized == "later",
           normalizedToken(at: index + 1, in: tokens) == "this",
           normalizedToken(at: index + 2, in: tokens) == "week",
           let date = laterThisWeek(from: now, calendar: calendar) {
            return BaseDateMatch(
                components: dateOnlyComponents(from: date, calendar: calendar),
                range: union(tokens[index].range, tokens[index + 2].range),
                endIndex: index + 2,
                source: .inferred
            )
        }

        if normalized == "this",
           normalizedToken(at: index + 1, in: tokens) == "weekend",
           let date = weekendDate(from: now, offsetWeeks: 0, calendar: calendar) {
            return BaseDateMatch(
                components: dateOnlyComponents(from: date, calendar: calendar),
                range: union(tokens[index].range, tokens[index + 1].range),
                endIndex: index + 1,
                source: .inferred
            )
        }

        if normalized == "next",
           let unit = normalizedToken(at: index + 1, in: tokens) {
            if unit == "weekend",
               let date = weekendDate(from: now, offsetWeeks: 1, calendar: calendar) {
                return BaseDateMatch(
                    components: dateOnlyComponents(from: date, calendar: calendar),
                    range: union(tokens[index].range, tokens[index + 1].range),
                    endIndex: index + 1,
                    source: .inferred
                )
            }

            if unit == "month",
               let date = calendar.date(byAdding: .month, value: 1, to: now) {
                return BaseDateMatch(
                    components: dateOnlyComponents(from: date, calendar: calendar),
                    range: union(tokens[index].range, tokens[index + 1].range),
                    endIndex: index + 1,
                    source: .inferred
                )
            }

            if unit == "year",
               let date = calendar.date(from: DateComponents(
                calendar: calendar,
                timeZone: calendar.timeZone,
                year: calendar.component(.year, from: now) + 1,
                month: 1,
                day: 1
               )) {
                return BaseDateMatch(
                    components: dateOnlyComponents(from: date, calendar: calendar),
                    range: union(tokens[index].range, tokens[index + 1].range),
                    endIndex: index + 1,
                    source: .inferred
                )
            }
        }

        if let calendarDate = QuickAddParsingSupport.parseCalendarDate(
            at: index,
            in: tokens,
            calendar: calendar,
            relativeTo: now
        ) {
            return BaseDateMatch(
                components: calendarDate.components,
                range: calendarDate.range,
                endIndex: calendarDate.endIndex,
                source: calendarDate.isExplicit ? .explicit : .inferred
            )
        }

        if let slashDate = parseSlashDate(normalized, calendar: calendar, now: now) {
            return BaseDateMatch(
                components: slashDate,
                range: tokens[index].range,
                endIndex: index,
                source: .inferred
            )
        }

        if let ordinalDayDate = parseOrdinalDayDate(normalized, calendar: calendar, now: now) {
            return BaseDateMatch(
                components: ordinalDayDate,
                range: tokens[index].range,
                endIndex: index,
                source: .inferred
            )
        }

        if let weekday = weekdayNumber(for: normalized),
           let date = nextWeekday(weekday, after: now, calendar: calendar) {
            return BaseDateMatch(
                components: dateOnlyComponents(from: date, calendar: calendar),
                range: tokens[index].range,
                endIndex: index,
                source: .inferred
            )
        }

        if let parsedDueDate = parseDueDate(tokens[index].text, calendar: calendar, now: now) {
            return BaseDateMatch(
                components: parsedDueDate,
                range: tokens[index].range,
                endIndex: index,
                source: .inferred
            )
        }

        return nil
    }

    private static func parseDueDate(
        _ token: String,
        calendar: Calendar,
        now: Date
    ) -> DateComponents? {
        let normalized = token.lowercased()

        switch normalized {
        case "today", "tod":
            return dateOnlyComponents(from: now, calendar: calendar)
        case "tomorrow", "tmr", "tom":
            guard let date = calendar.date(byAdding: .day, value: 1, to: now) else {
                return nil
            }
            return dateOnlyComponents(from: date, calendar: calendar)
        default:
            return nil
        }
    }

    private static func parseDaypartExpression(
        at index: Int,
        in tokens: [QuickAddScannedToken],
        calendar: Calendar,
        now: Date
    ) -> ScheduleMatch? {
        let normalized = normalizedToken(at: index, in: tokens)

        if normalized == "in",
           normalizedToken(at: index + 1, in: tokens) == "the",
           let period = normalizedToken(at: index + 2, in: tokens),
           let time = fixedTime(forPeriod: period),
           let components = nextTimeOccurrenceComponents(
            hour: time.hour,
            minute: time.minute,
            from: now,
            calendar: calendar
           ) {
            return ScheduleMatch(
                components: components,
                kind: .time,
                range: union(tokens[index].range, tokens[index + 2].range),
                endIndex: index + 2,
                source: .inferred
            )
        }

        return nil
    }

    private static func parseSignedRelativeDuration(
        at index: Int,
        in tokens: [QuickAddScannedToken],
        calendar: Calendar,
        now: Date
    ) -> ScheduleMatch? {
        guard let amountToken = normalizedToken(at: index, in: tokens),
              amountToken.hasPrefix("+"),
              let amount = parseRelativeAmount(amountToken),
              amount > 0,
              let unitToken = normalizedToken(at: index + 1, in: tokens),
              let unit = RelativeUnit(unitToken) else {
            return nil
        }

        guard let relative = relativeDuration(
            amount: amount,
            unit: unit,
            from: now,
            range: union(tokens[index].range, tokens[index + 1].range),
            endIndex: index + 1,
            calendar: calendar
        ) else {
            return nil
        }

        return ScheduleMatch(
            components: relative.components,
            kind: relative.kind,
            range: relative.range,
            endIndex: relative.endIndex,
            source: .inferred
        )
    }

    private static func parseDateMathExpression(
        at index: Int,
        in tokens: [QuickAddScannedToken],
        calendar: Calendar,
        now: Date
    ) -> ScheduleMatch? {
        guard let amountToken = normalizedToken(at: index, in: tokens),
              let amount = parseRelativeAmount(amountToken),
              amount > 0,
              let unitToken = normalizedToken(at: index + 1, in: tokens),
              let unit = RelativeUnit(unitToken),
              let direction = normalizedToken(at: index + 2, in: tokens),
              direction == "from" || direction == "after" || direction == "before",
              let baseDate = parseBaseDateExpression(at: index + 3, in: tokens, calendar: calendar, now: now),
              let base = calendar.date(from: baseDate.components) else {
            return nil
        }

        let value = direction == "before" ? -amount : amount
        let component: Calendar.Component

        switch unit {
        case .day:
            component = .day
        case .week:
            component = .weekOfYear
        case .minute, .hour:
            return nil
        }

        guard let date = calendar.date(byAdding: component, value: value, to: base) else {
            return nil
        }

        return ScheduleMatch(
            components: dateOnlyComponents(from: date, calendar: calendar),
            kind: .date,
            range: union(tokens[index].range, baseDate.range),
            endIndex: baseDate.endIndex,
            source: .inferred
        )
    }

    private static func parseSlashDate(
        _ token: String,
        calendar: Calendar,
        now: Date
    ) -> DateComponents? {
        guard let match = token.firstMatch(of: /^(\d{1,2})\/(\d{1,2})(?:\/(\d{2}|\d{4}))?$/),
              let month = Int(match.1),
              let day = Int(match.2) else {
            return nil
        }

        let year = match.3.flatMap { yearToken -> Int? in
            guard let parsedYear = Int(yearToken) else {
                return nil
            }

            return parsedYear < 100 ? 2000 + parsedYear : parsedYear
        }

        if let year {
            return dateComponents(year: year, month: month, day: day, calendar: calendar)
        }

        return QuickAddParsingSupport.upcomingDate(
            month: month,
            day: day,
            calendar: calendar,
            referenceDate: now
        )
    }

    private static func parseOrdinalDayDate(
        _ token: String,
        calendar: Calendar,
        now: Date
    ) -> DateComponents? {
        guard token.firstMatch(of: /^\d{1,2}(st|nd|rd|th)$/) != nil,
              let day = parseDayNumber(token) else {
            return nil
        }

        let month = calendar.component(.month, from: now)
        let year = calendar.component(.year, from: now)

        if let components = dateComponents(year: year, month: month, day: day, calendar: calendar),
           let date = calendar.date(from: components),
           date >= startOfDay(for: now, calendar: calendar) {
            return components
        }

        guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: now) else {
            return nil
        }

        return dateComponents(
            year: calendar.component(.year, from: nextMonth),
            month: calendar.component(.month, from: nextMonth),
            day: day,
            calendar: calendar
        )
    }

    private static func dateComponents(
        year: Int,
        month: Int,
        day: Int,
        calendar: Calendar
    ) -> DateComponents? {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day

        guard let date = calendar.date(from: components),
              calendar.component(.year, from: date) == year,
              calendar.component(.month, from: date) == month,
              calendar.component(.day, from: date) == day else {
            return nil
        }

        return dateOnlyComponents(from: date, calendar: calendar)
    }

    private static func parseRelativeDate(
        at index: Int,
        in tokens: [QuickAddScannedToken],
        calendar: Calendar,
        now: Date
    ) -> (components: DateComponents, kind: QuickAddToken.Kind, range: NSRange, endIndex: Int)? {
        let normalized = normalizedToken(at: index, in: tokens)

        switch normalized {
        case "tonight":
            return fixedTimeRelativeDate(
                from: now,
                hour: 18,
                minute: 0,
                range: tokens[index].range,
                endIndex: index,
                calendar: calendar
            )
        case "afternoon":
            return fixedTimeRelativeDate(
                from: now,
                hour: 14,
                minute: 0,
                range: tokens[index].range,
                endIndex: index,
                calendar: calendar
            )
        case "evening":
            return fixedTimeRelativeDate(
                from: now,
                hour: 18,
                minute: 0,
                range: tokens[index].range,
                endIndex: index,
                calendar: calendar
            )
        default:
            break
        }

        if let compactDuration = parseCompactDuration(normalized ?? ""),
           compactDuration.amount > 0 {
            return relativeDuration(
                amount: compactDuration.amount,
                unit: compactDuration.unit,
                from: now,
                range: tokens[index].range,
                endIndex: index,
                calendar: calendar
            )
        }

        if normalized == "later",
           normalizedToken(at: index + 1, in: tokens) == "today" {
            return fixedTimeRelativeDate(
                from: now,
                hour: 17,
                minute: 0,
                range: union(tokens[index].range, tokens[index + 1].range),
                endIndex: index + 1,
                calendar: calendar
            )
        }

        if normalized == "this",
           let period = normalizedToken(at: index + 1, in: tokens),
           let time = fixedTime(forPeriod: period) {
            return fixedTimeRelativeDate(
                from: now,
                hour: time.hour,
                minute: time.minute,
                range: union(tokens[index].range, tokens[index + 1].range),
                endIndex: index + 1,
                calendar: calendar
            )
        }

        if normalized == "next",
           let unit = normalizedToken(at: index + 1, in: tokens),
           unit == "week",
           let date = calendar.date(byAdding: .weekOfYear, value: 1, to: now) {
            return (
                dateOnlyComponents(from: date, calendar: calendar),
                .date,
                union(tokens[index].range, tokens[index + 1].range),
                index + 1
            )
        }

        if normalized == "next",
           let weekdayToken = normalizedToken(at: index + 1, in: tokens),
           let weekday = weekdayNumber(for: weekdayToken),
           let date = nextWeekday(weekday, after: now, calendar: calendar) {
            return (
                dateOnlyComponents(from: date, calendar: calendar),
                .date,
                union(tokens[index].range, tokens[index + 1].range),
                index + 1
            )
        }

        if normalized == "in",
           let duration = parseRelativeDurationPhrase(at: index + 1, in: tokens),
           duration.amount > 0 {
            return relativeDuration(
                amount: duration.amount,
                unit: duration.unit,
                from: now,
                range: union(tokens[index].range, tokens[duration.endIndex].range),
                endIndex: duration.endIndex,
                calendar: calendar
            )
        }

        return nil
    }

    private static func parseRelativeAmount(_ token: String) -> Int? {
        let normalized = token.hasPrefix("+") ? String(token.dropFirst()) : token

        switch normalized {
        case "a", "an", "one":
            return 1
        default:
            return Int(normalized)
        }
    }

    private static func parseRelativeDurationPhrase(
        at index: Int,
        in tokens: [QuickAddScannedToken]
    ) -> RelativeDurationMatch? {
        guard let firstToken = normalizedToken(at: index, in: tokens) else {
            return nil
        }

        if let compactDuration = parseCompactDuration(firstToken) {
            return RelativeDurationMatch(
                amount: compactDuration.amount,
                unit: compactDuration.unit,
                endIndex: index
            )
        }

        if firstToken == "half" {
            if let unitToken = normalizedToken(at: index + 1, in: tokens),
               let unit = RelativeUnit(unitToken) {
                return halfDuration(for: unit, endIndex: index + 1)
            }

            if (normalizedToken(at: index + 1, in: tokens) == "an" ||
                normalizedToken(at: index + 1, in: tokens) == "a"),
               let unitToken = normalizedToken(at: index + 2, in: tokens),
               let unit = RelativeUnit(unitToken) {
                return halfDuration(for: unit, endIndex: index + 2)
            }
        }

        guard let amount = parseRelativeAmountExpression(at: index, in: tokens),
              let unitToken = normalizedToken(at: amount.endIndex + 1, in: tokens),
              let unit = RelativeUnit(unitToken) else {
            return nil
        }

        return RelativeDurationMatch(amount: amount.value, unit: unit, endIndex: amount.endIndex + 1)
    }

    private static func halfDuration(for unit: RelativeUnit, endIndex: Int) -> RelativeDurationMatch? {
        switch unit {
        case .minute:
            return nil
        case .hour:
            return RelativeDurationMatch(amount: 30, unit: .minute, endIndex: endIndex)
        case .day:
            return RelativeDurationMatch(amount: 12, unit: .hour, endIndex: endIndex)
        case .week:
            return nil
        }
    }

    private static func parseRelativeAmountExpression(
        at index: Int,
        in tokens: [QuickAddScannedToken]
    ) -> (value: Int, endIndex: Int)? {
        guard let firstToken = normalizedToken(at: index, in: tokens) else {
            return nil
        }

        if (firstToken == "a" || firstToken == "an"),
           let secondToken = normalizedToken(at: index + 1, in: tokens),
           let fuzzy = parseFuzzyRelativeAmount(secondToken) {
            return (fuzzy, optionalOfEndIndex(after: index + 1, in: tokens))
        }

        if let fuzzy = parseFuzzyRelativeAmount(firstToken) {
            return (fuzzy, optionalOfEndIndex(after: index, in: tokens))
        }

        if let amount = parseRelativeAmount(firstToken) {
            return (amount, index)
        }

        return parseSpelledNumber(at: index, in: tokens)
    }

    private static func parseFuzzyRelativeAmount(_ token: String) -> Int? {
        switch token {
        case "couple":
            return 2
        case "few":
            return 3
        default:
            return nil
        }
    }

    private static func optionalOfEndIndex(after index: Int, in tokens: [QuickAddScannedToken]) -> Int {
        normalizedToken(at: index + 1, in: tokens) == "of" ? index + 1 : index
    }

    private static func parseSpelledNumber(
        at index: Int,
        in tokens: [QuickAddScannedToken]
    ) -> (value: Int, endIndex: Int)? {
        guard let firstToken = normalizedToken(at: index, in: tokens),
              let firstValue = spelledNumberValue(firstToken) else {
            return nil
        }

        if firstValue >= 20,
           firstValue % 10 == 0,
           let secondToken = normalizedToken(at: index + 1, in: tokens),
           let secondValue = spelledNumberValue(secondToken),
           (1...9).contains(secondValue) {
            return (firstValue + secondValue, index + 1)
        }

        return (firstValue, index)
    }

    private static func spelledNumberValue(_ token: String) -> Int? {
        let normalized = token.replacingOccurrences(of: "-", with: " ")

        if normalized.contains(" ") {
            let parts = normalized.split(separator: " ").map(String.init)
            guard parts.count == 2,
                  let tens = spelledNumberValue(parts[0]),
                  tens >= 20,
                  tens % 10 == 0,
                  let ones = spelledNumberValue(parts[1]),
                  (1...9).contains(ones) else {
                return nil
            }

            return tens + ones
        }

        switch normalized {
        case "zero":
            return 0
        case "one":
            return 1
        case "two":
            return 2
        case "three":
            return 3
        case "four":
            return 4
        case "five":
            return 5
        case "six":
            return 6
        case "seven":
            return 7
        case "eight":
            return 8
        case "nine":
            return 9
        case "ten":
            return 10
        case "eleven":
            return 11
        case "twelve":
            return 12
        case "thirteen":
            return 13
        case "fourteen":
            return 14
        case "fifteen":
            return 15
        case "sixteen":
            return 16
        case "seventeen":
            return 17
        case "eighteen":
            return 18
        case "nineteen":
            return 19
        case "twenty":
            return 20
        case "thirty":
            return 30
        case "forty":
            return 40
        case "fifty":
            return 50
        case "sixty":
            return 60
        case "seventy":
            return 70
        case "eighty":
            return 80
        case "ninety":
            return 90
        default:
            return nil
        }
    }

    private static func parseCompactDuration(_ token: String) -> (amount: Int, unit: RelativeUnit)? {
        guard let match = token.firstMatch(of: /^\+?(\d+)(m|mins?|h|hrs?|d|w)$/),
              let amount = Int(match.1),
              let unit = RelativeUnit(String(match.2)) else {
            return nil
        }

        return (amount, unit)
    }

    private static func relativeDuration(
        amount: Int,
        unit: RelativeUnit,
        from now: Date,
        range: NSRange,
        endIndex: Int,
        calendar: Calendar
    ) -> (components: DateComponents, kind: QuickAddToken.Kind, range: NSRange, endIndex: Int)? {
        switch unit {
        case .minute:
            guard let date = calendar.date(byAdding: .minute, value: amount, to: now) else {
                return nil
            }
            return (dateAndTimeComponents(from: date, calendar: calendar), .time, range, endIndex)
        case .hour:
            guard let date = calendar.date(byAdding: .hour, value: amount, to: now) else {
                return nil
            }
            return (dateAndTimeComponents(from: date, calendar: calendar), .time, range, endIndex)
        case .day:
            guard let date = calendar.date(byAdding: .day, value: amount, to: now) else {
                return nil
            }
            return (dateOnlyComponents(from: date, calendar: calendar), .date, range, endIndex)
        case .week:
            guard let date = calendar.date(byAdding: .weekOfYear, value: amount, to: now) else {
                return nil
            }
            return (dateOnlyComponents(from: date, calendar: calendar), .date, range, endIndex)
        }
    }

    private enum RelativeUnit {
        case minute
        case hour
        case day
        case week

        init?(_ token: String) {
            switch token {
            case "m", "minute", "minutes", "min", "mins":
                self = .minute
            case "h", "hour", "hours", "hr", "hrs":
                self = .hour
            case "d", "day", "days":
                self = .day
            case "w", "week", "weeks":
                self = .week
            default:
                return nil
            }
        }
    }

    private static func normalizedToken(at index: Int, in tokens: [QuickAddScannedToken]) -> String? {
        guard tokens.indices.contains(index) else {
            return nil
        }

        return QuickAddParsingSupport.normalized(tokens[index].text)
    }

    private static func fixedTime(forPeriod period: String) -> (hour: Int, minute: Int)? {
        switch period {
        case "morning":
            return (9, 0)
        case "afternoon":
            return (14, 0)
        case "evening":
            return (18, 0)
        case "tonight":
            return (18, 0)
        default:
            return nil
        }
    }

    private static func followingTimeExpression(
        after index: Int,
        in tokens: [QuickAddScannedToken],
        metadata: QuickAddReminderMetadataMatches
    ) -> (time: ParsedTime, range: NSRange, startIndex: Int, endIndex: Int)? {
        let nextIndex = nextScheduleIndex(
            after: index,
            in: tokens,
            metadata: metadata
        )

        guard nextIndex < tokens.count else {
            return nil
        }

        if tokens[nextIndex].text.lowercased() == "at" {
            let timeIndex = nextIndex + 1

            guard timeIndex < tokens.count,
                  let time = parseTime(tokens[timeIndex].text) else {
                return nil
            }

            return (
                time,
                union(tokens[nextIndex].range, tokens[timeIndex].range),
                nextIndex,
                timeIndex
            )
        }

        if let period = normalizedToken(at: nextIndex, in: tokens),
           let fixedTime = fixedTime(forPeriod: period) {
            return (
                ParsedTime(hour: fixedTime.hour, minute: fixedTime.minute, hasMeridiem: false, hasColon: false),
                tokens[nextIndex].range,
                nextIndex,
                nextIndex
            )
        }

        guard let time = parseTime(tokens[nextIndex].text),
              time.hasMeridiem || time.hasColon else {
            return nil
        }

        return (time, tokens[nextIndex].range, nextIndex, nextIndex)
    }

    private static func nextScheduleIndex(
        after index: Int,
        in tokens: [QuickAddScannedToken],
        metadata: QuickAddReminderMetadataMatches
    ) -> Int {
        var nextIndex = index + 1

        while true {
            if let earlyReminder = metadata.earlyReminders.first(where: {
                $0.startIndex == nextIndex
            }) {
                nextIndex = earlyReminder.endIndex + 1
                continue
            }

            if metadata.urls.contains(where: { $0.index == nextIndex }) {
                nextIndex += 1
                continue
            }

            if tokens.indices.contains(nextIndex),
               QuickAddParsingSupport.isSingleTokenReminderMetadata(tokens[nextIndex]) {
                nextIndex += 1
                continue
            }

            return nextIndex
        }
    }

    private static func parseTimeOnlyExpression(
        at index: Int,
        in tokens: [QuickAddScannedToken],
        calendar: Calendar,
        now: Date
    ) -> ScheduleMatch? {
        guard let parsedTime = parseTime(tokens[index].text),
              parsedTime.hasMeridiem || parsedTime.hasColon else {
            return nil
        }

        guard let components = nextTimeOccurrenceComponents(
            hour: parsedTime.hour,
            minute: parsedTime.minute,
            from: now,
            calendar: calendar
        ) else {
            return nil
        }

        return ScheduleMatch(
            components: components,
            kind: .time,
            range: tokens[index].range,
            endIndex: index,
            source: .inferred
        )
    }

    private static func parseDayNumber(_ token: String) -> Int? {
        let cleaned = token.replacing(/(st|nd|rd|th)$/, with: "")

        guard let day = Int(cleaned),
              (1...31).contains(day) else {
            return nil
        }

        return day
    }

    private static func laterThisWeek(from date: Date, calendar: Calendar) -> Date? {
        guard let friday = upcomingWeekday(6, onOrAfter: date, calendar: calendar),
              !calendar.isDate(friday, inSameDayAs: date) else {
            return calendar.date(byAdding: .day, value: 2, to: date)
        }

        return friday
    }

    private static func weekendDate(from date: Date, offsetWeeks: Int, calendar: Calendar) -> Date? {
        guard let saturday = upcomingWeekday(7, onOrAfter: date, calendar: calendar) else {
            return nil
        }

        guard offsetWeeks > 0 else {
            return saturday
        }

        return calendar.date(byAdding: .weekOfYear, value: offsetWeeks, to: saturday)
    }

    private static func upcomingWeekday(_ weekday: Int, onOrAfter date: Date, calendar: Calendar) -> Date? {
        let currentWeekday = calendar.component(.weekday, from: date)
        var daysUntilWeekday = weekday - currentWeekday

        if daysUntilWeekday < 0 {
            daysUntilWeekday += 7
        }

        return calendar.date(byAdding: .day, value: daysUntilWeekday, to: date)
    }

    private static func startOfDay(for date: Date, calendar: Calendar) -> Date {
        calendar.startOfDay(for: date)
    }

    private static func fixedTimeRelativeDate(
        from date: Date,
        hour: Int,
        minute: Int,
        range: NSRange,
        endIndex: Int,
        calendar: Calendar
    ) -> (components: DateComponents, kind: QuickAddToken.Kind, range: NSRange, endIndex: Int)? {
        guard let components = nextTimeOccurrenceComponents(
            hour: hour,
            minute: minute,
            from: date,
            calendar: calendar
        ) else {
            return nil
        }

        return (components, .time, range, endIndex)
    }

    private static func nextTimeOccurrenceComponents(
        hour: Int,
        minute: Int,
        from date: Date,
        calendar: Calendar
    ) -> DateComponents? {
        let time = ParsedTime(
            hour: hour,
            minute: minute,
            hasMeridiem: false,
            hasColon: false
        )
        guard var components = QuickAddParsingSupport.applying(
            time,
            to: dateOnlyComponents(from: date, calendar: calendar),
            calendar: calendar
        ), let candidate = calendar.date(from: components) else {
            return nil
        }

        if candidate <= date,
           let tomorrow = calendar.date(byAdding: .day, value: 1, to: date) {
            guard let nextComponents = QuickAddParsingSupport.applying(
                time,
                to: dateOnlyComponents(from: tomorrow, calendar: calendar),
                calendar: calendar
            ) else {
                return nil
            }

            components = nextComponents
        }

        return components
    }

    private static func weekdayNumber(for token: String) -> Int? {
        QuickAddParsingSupport.weekday(for: token)?.rawValue
    }

    private static func nextWeekday(_ weekday: Int, after date: Date, calendar: Calendar) -> Date? {
        let currentWeekday = calendar.component(.weekday, from: date)
        var daysUntilWeekday = weekday - currentWeekday

        if daysUntilWeekday <= 0 {
            daysUntilWeekday += 7
        }

        return calendar.date(byAdding: .day, value: daysUntilWeekday, to: date)
    }

    private static func union(_ lhs: NSRange, _ rhs: NSRange) -> NSRange {
        QuickAddParsingSupport.union(lhs, rhs)
    }

    private static func parseTime(_ token: String) -> ParsedTime? {
        QuickAddParsingSupport.parseTime(token)
    }

    private static func dateOnlyComponents(from date: Date, calendar: Calendar) -> DateComponents {
        calendar.dateComponents([.calendar, .timeZone, .year, .month, .day], from: date)
    }

    private static func dateAndTimeComponents(from date: Date, calendar: Calendar) -> DateComponents {
        calendar.dateComponents([.calendar, .timeZone, .year, .month, .day, .hour, .minute], from: date)
    }
}
