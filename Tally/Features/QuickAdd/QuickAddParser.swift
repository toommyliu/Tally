import Foundation

struct QuickAddFields: Equatable {
    var title: String
    var listName: String?
    var tags: [String]
    var inlineNotes: String?
    var dueDate: DateComponents?
    var priority: Int
    var usedTokens: [QuickAddToken]
}

struct QuickAddToken: Equatable {
    enum Kind: Equatable {
        case list
        case tag
        case date
        case time
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
        suppressedInferredTokens: [QuickAddSuppressedToken] = []
    ) -> QuickAddFields {
        var titleTokens: [String] = []
        var listName: String?
        var tags: [String] = []
        var inlineNotes: String?
        var dueDate: DateComponents?
        var priority = 0
        var usedTokens: [QuickAddToken] = []
        let tokens = scanTokens(in: input)
        var index = 0

        while index < tokens.count {
            let token = tokens[index]

            if tokenStartsInlineNotes(token) {
                inlineNotes = noteText(from: token, in: input)
                usedTokens.append(QuickAddToken(kind: .note, range: noteRange(from: token, in: input)))
                break
            }

            if isInsideSuppressedToken(token, in: input, suppressedInferredTokens: suppressedInferredTokens) {
                titleTokens.append(token.text)
                index += 1
                continue
            }

            if token.text.hasPrefix("#"), token.text.count > 1 {
                listName = QuickAddListTokenCodec.decode(String(token.text.dropFirst()))
                usedTokens.append(QuickAddToken(kind: .list, range: token.range))
                index += 1
                continue
            }

            if token.text.hasPrefix("@"), token.text.count > 1 {
                tags.append(String(token.text.dropFirst()))
                usedTokens.append(QuickAddToken(kind: .tag, range: token.range))
                index += 1
                continue
            }

            if let parsedPriority = parsePriority(token.text) {
                priority = parsedPriority
                usedTokens.append(QuickAddToken(kind: .priority, range: token.range))
                index += 1
                continue
            }

            if dueDate == nil,
               let parsedSchedule = parseScheduleExpression(at: index, in: tokens, calendar: calendar, now: now) {
                dueDate = parsedSchedule.components
                usedTokens.append(QuickAddToken(
                    kind: parsedSchedule.kind,
                    range: parsedSchedule.range,
                    source: parsedSchedule.source
                ))
                index = parsedSchedule.endIndex + 1
                continue
            }

            titleTokens.append(token.text)
            index += 1
        }

        return QuickAddFields(
            title: titleTokens.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines),
            listName: listName,
            tags: tags,
            inlineNotes: inlineNotes,
            dueDate: dueDate,
            priority: priority,
            usedTokens: usedTokens
        )
    }

    private struct ScannedToken {
        var text: String
        var range: NSRange
    }

    private struct ScheduleMatch {
        var components: DateComponents
        var kind: QuickAddToken.Kind
        var range: NSRange
        var endIndex: Int
        var source: QuickAddToken.Source
    }

    private struct BaseDateMatch {
        var components: DateComponents
        var range: NSRange
        var endIndex: Int
        var source: QuickAddToken.Source
    }

    private struct ParsedTime {
        var hour: Int
        var minute: Int
        var hasMeridiem: Bool
        var hasColon: Bool
    }

    private struct RelativeDurationMatch {
        var amount: Int
        var unit: RelativeUnit
        var endIndex: Int
    }

    private static func scanTokens(in input: String) -> [ScannedToken] {
        var tokens: [ScannedToken] = []
        var index = input.startIndex

        while index < input.endIndex {
            while index < input.endIndex, input[index].isWhitespace {
                index = input.index(after: index)
            }

            guard index < input.endIndex else {
                break
            }

            let start = index

            while index < input.endIndex, !input[index].isWhitespace {
                index = input.index(after: index)
            }

            let text = String(input[start..<index])
            let location = input.utf16.distance(from: input.utf16.startIndex, to: start.samePosition(in: input.utf16)!)
            let length = text.utf16.count
            tokens.append(ScannedToken(text: text, range: NSRange(location: location, length: length)))
        }

        return tokens
    }

    private static func tokenStartsInlineNotes(_ token: ScannedToken) -> Bool {
        token.text.hasPrefix("//")
    }

    private static func noteRange(from token: ScannedToken, in input: String) -> NSRange {
        let fullLength = (input as NSString).length
        return NSRange(location: token.range.location, length: fullLength - token.range.location)
    }

    private static func noteText(from token: ScannedToken, in input: String) -> String? {
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
        _ token: ScannedToken,
        in input: String,
        suppressedInferredTokens: [QuickAddSuppressedToken]
    ) -> Bool {
        let originalText = input as NSString

        return suppressedInferredTokens.contains { suppressedToken in
            guard NSLocationInRange(token.range.location, suppressedToken.range),
                  NSMaxRange(suppressedToken.range) <= originalText.length else {
                return false
            }

            return originalText.substring(with: suppressedToken.range) == suppressedToken.text
        }
    }

    private static func parseScheduleExpression(
        at index: Int,
        in tokens: [ScannedToken],
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
            var kind = relativeDate.kind
            var range = relativeDate.range
            var endIndex = relativeDate.endIndex

            if components.hour == nil,
               let time = followingTimeExpression(after: endIndex, in: tokens) {
                components.hour = time.time.hour
                components.minute = time.time.minute
                kind = .time
                range = union(range, time.range)
                endIndex = time.endIndex
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
            var kind: QuickAddToken.Kind = .date
            var range = baseDate.range
            var endIndex = baseDate.endIndex

            if let time = followingTimeExpression(after: endIndex, in: tokens) {
                components.hour = time.time.hour
                components.minute = time.time.minute
                kind = .time
                range = union(range, time.range)
                endIndex = time.endIndex
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
        in tokens: [ScannedToken],
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

        if let monthDate = parseMonthDayDate(at: index, in: tokens, calendar: calendar, now: now) {
            return monthDate
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
            let source: QuickAddToken.Source = parseISODate(normalized, calendar: calendar) == nil ? .inferred : .explicit
            return BaseDateMatch(
                components: parsedDueDate,
                range: tokens[index].range,
                endIndex: index,
                source: source
            )
        }

        return nil
    }

    private static func parsePriority(_ token: String) -> Int? {
        switch token.lowercased() {
        case "p1":
            return 1
        case "p2":
            return 5
        case "p3":
            return 9
        case "p4":
            return 0
        default:
            return nil
        }
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
            return parseISODate(normalized, calendar: calendar)
        }
    }

    private static func parseISODate(_ token: String, calendar: Calendar) -> DateComponents? {
        let parts = token.split(separator: "-", omittingEmptySubsequences: false)

        guard parts.count == 3,
              parts[0].count == 4,
              parts[1].count == 2,
              parts[2].count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2])
        else {
            return nil
        }

        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day

        guard let date = calendar.date(from: components),
              calendar.component(.year, from: date) == year,
              calendar.component(.month, from: date) == month,
              calendar.component(.day, from: date) == day
        else {
            return nil
        }

        return dateOnlyComponents(from: date, calendar: calendar)
    }

    private static func parseDaypartExpression(
        at index: Int,
        in tokens: [ScannedToken],
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
        in tokens: [ScannedToken],
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
        in tokens: [ScannedToken],
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

    private static func parseMonthDayDate(
        at index: Int,
        in tokens: [ScannedToken],
        calendar: Calendar,
        now: Date
    ) -> BaseDateMatch? {
        guard let first = normalizedToken(at: index, in: tokens) else {
            return nil
        }

        if let month = monthNumber(for: first),
           let second = normalizedToken(at: index + 1, in: tokens),
           let day = parseDayNumber(second),
           let components = upcomingDate(month: month, day: day, calendar: calendar, now: now) {
            return BaseDateMatch(
                components: components,
                range: union(tokens[index].range, tokens[index + 1].range),
                endIndex: index + 1,
                source: .inferred
            )
        }

        if let day = parseDayNumber(first),
           let second = normalizedToken(at: index + 1, in: tokens),
           let month = monthNumber(for: second),
           let components = upcomingDate(month: month, day: day, calendar: calendar, now: now) {
            return BaseDateMatch(
                components: components,
                range: union(tokens[index].range, tokens[index + 1].range),
                endIndex: index + 1,
                source: .inferred
            )
        }

        return nil
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

        return upcomingDate(month: month, day: day, calendar: calendar, now: now)
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

    private static func upcomingDate(
        month: Int,
        day: Int,
        calendar: Calendar,
        now: Date
    ) -> DateComponents? {
        let currentYear = calendar.component(.year, from: now)

        guard let currentYearDate = dateComponents(year: currentYear, month: month, day: day, calendar: calendar),
              let date = calendar.date(from: currentYearDate) else {
            return nil
        }

        if date >= startOfDay(for: now, calendar: calendar) {
            return currentYearDate
        }

        return dateComponents(year: currentYear + 1, month: month, day: day, calendar: calendar)
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
        in tokens: [ScannedToken],
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
        in tokens: [ScannedToken]
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
        in tokens: [ScannedToken]
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

    private static func optionalOfEndIndex(after index: Int, in tokens: [ScannedToken]) -> Int {
        normalizedToken(at: index + 1, in: tokens) == "of" ? index + 1 : index
    }

    private static func parseSpelledNumber(
        at index: Int,
        in tokens: [ScannedToken]
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

    private static func normalizedToken(at index: Int, in tokens: [ScannedToken]) -> String? {
        guard tokens.indices.contains(index) else {
            return nil
        }

        return tokens[index].text
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,;"))
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
        in tokens: [ScannedToken]
    ) -> (time: ParsedTime, range: NSRange, endIndex: Int)? {
        let nextIndex = index + 1

        guard nextIndex < tokens.count else {
            return nil
        }

        if tokens[nextIndex].text.lowercased() == "at" {
            let timeIndex = nextIndex + 1

            guard timeIndex < tokens.count,
                  let time = parseTime(tokens[timeIndex].text) else {
                return nil
            }

            return (time, union(tokens[nextIndex].range, tokens[timeIndex].range), timeIndex)
        }

        if let period = normalizedToken(at: nextIndex, in: tokens),
           let fixedTime = fixedTime(forPeriod: period) {
            return (
                ParsedTime(hour: fixedTime.hour, minute: fixedTime.minute, hasMeridiem: false, hasColon: false),
                tokens[nextIndex].range,
                nextIndex
            )
        }

        guard let time = parseTime(tokens[nextIndex].text),
              time.hasMeridiem || time.hasColon else {
            return nil
        }

        return (time, tokens[nextIndex].range, nextIndex)
    }

    private static func parseTimeOnlyExpression(
        at index: Int,
        in tokens: [ScannedToken],
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

    private static func monthNumber(for token: String) -> Int? {
        switch token {
        case "january", "jan":
            return 1
        case "february", "feb":
            return 2
        case "march", "mar":
            return 3
        case "april", "apr":
            return 4
        case "may":
            return 5
        case "june", "jun":
            return 6
        case "july", "jul":
            return 7
        case "august", "aug":
            return 8
        case "september", "sep", "sept":
            return 9
        case "october", "oct":
            return 10
        case "november", "nov":
            return 11
        case "december", "dec":
            return 12
        default:
            return nil
        }
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
        var components = dateOnlyComponents(from: date, calendar: calendar)
        components.hour = hour
        components.minute = minute
        return (components, .time, range, endIndex)
    }

    private static func nextTimeOccurrenceComponents(
        hour: Int,
        minute: Int,
        from date: Date,
        calendar: Calendar
    ) -> DateComponents? {
        var components = dateOnlyComponents(from: date, calendar: calendar)
        components.hour = hour
        components.minute = minute

        guard let candidate = calendar.date(from: components) else {
            return nil
        }

        if candidate <= date,
           let tomorrow = calendar.date(byAdding: .day, value: 1, to: date) {
            components = dateOnlyComponents(from: tomorrow, calendar: calendar)
            components.hour = hour
            components.minute = minute
        }

        return components
    }

    private static func weekdayNumber(for token: String) -> Int? {
        switch token {
        case "sunday", "sun":
            return 1
        case "monday", "mon":
            return 2
        case "tuesday", "tue", "tues":
            return 3
        case "wednesday", "wed":
            return 4
        case "thursday", "thu", "thur", "thurs":
            return 5
        case "friday", "fri":
            return 6
        case "saturday", "sat":
            return 7
        default:
            return nil
        }
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
        let start = min(lhs.location, rhs.location)
        let end = max(NSMaxRange(lhs), NSMaxRange(rhs))
        return NSRange(location: start, length: end - start)
    }

    private static func parseTime(_ token: String) -> ParsedTime? {
        let normalized = token
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,;"))

        guard let match = normalized.firstMatch(of: /^(\d{1,2})(?::(\d{2}))?(am|pm)?$/) else {
            return nil
        }

        guard var hour = Int(match.1) else {
            return nil
        }

        let minute = match.2.flatMap { Int($0) } ?? 0
        let meridiem = match.3.map(String.init)
        let hasColon = match.2 != nil

        guard (0...59).contains(minute) else {
            return nil
        }

        if let meridiem {
            guard (1...12).contains(hour) else {
                return nil
            }

            if meridiem == "pm", hour < 12 {
                hour += 12
            } else if meridiem == "am", hour == 12 {
                hour = 0
            }
        } else {
            guard (0...23).contains(hour) else {
                return nil
            }
        }

        return ParsedTime(
            hour: hour,
            minute: minute,
            hasMeridiem: meridiem != nil,
            hasColon: hasColon
        )
    }

    private static func dateOnlyComponents(from date: Date, calendar: Calendar) -> DateComponents {
        calendar.dateComponents([.calendar, .timeZone, .year, .month, .day], from: date)
    }

    private static func dateAndTimeComponents(from date: Date, calendar: Calendar) -> DateComponents {
        calendar.dateComponents([.calendar, .timeZone, .year, .month, .day, .hour, .minute], from: date)
    }
}
