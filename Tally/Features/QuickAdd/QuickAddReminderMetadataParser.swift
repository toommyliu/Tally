import Foundation

struct QuickAddRecurrenceMatch {
    let recurrence: ReminderRecurrence
    let dueDate: DateComponents
    let dueDateWithoutTime: DateComponents
    let range: NSRange
    let startIndex: Int
    let endIndex: Int
    let detachedTokens: [QuickAddRecurrenceTokenMatch]
}

/// A contiguous recurrence segment separated from the primary phrase by other metadata.
struct QuickAddRecurrenceTokenMatch {
    let range: NSRange
    let startIndex: Int
    let endIndex: Int
    let includesTime: Bool
    let includesEnd: Bool
}

/// A recurrence-shaped phrase whose explicit end clause is invalid.
struct QuickAddInvalidRecurrenceMatch {
    let startIndex: Int
    let endIndex: Int
}

struct QuickAddEarlyReminderMatch {
    let earlyReminder: ReminderEarlyReminder
    let range: NSRange
    let startIndex: Int
    let endIndex: Int
}

struct QuickAddURLMatch {
    let url: URL
    let range: NSRange
    let index: Int
}

struct QuickAddReminderMetadataMatches {
    let recurrences: [QuickAddRecurrenceMatch]
    let invalidRecurrences: [QuickAddInvalidRecurrenceMatch]
    let earlyReminders: [QuickAddEarlyReminderMatch]
    let urls: [QuickAddURLMatch]
}

/// Parses reminder metadata that is independent from one-off date language.
enum QuickAddReminderMetadataParser {
    private struct TrimmedURLText {
        let value: String
        let leadingUTF16Length: Int
        let usedUTF16Length: Int
    }

    private enum RecurrenceAnchor {
        case today
        case nextWeekday(ReminderWeekday)
        case nextBusinessDay
        case offset(Calendar.Component, Int)
    }

    private struct RecurrencePattern {
        let recurrence: ReminderRecurrence
        let anchor: RecurrenceAnchor
        let endIndex: Int
    }

    private struct RecurrenceEndMatch {
        let value: ReminderRecurrenceEnd
        let startIndex: Int
        let endIndex: Int
    }

    private struct RecurrenceTimeMatch {
        let time: QuickAddParsedTime
        let startIndex: Int
        let endIndex: Int
    }

    private struct RecurrenceTokenSpan {
        var startIndex: Int
        var endIndex: Int
        var includesTime: Bool
        var includesEnd: Bool
    }

    private enum RecurrenceEndResult {
        case absent
        case invalid(endIndex: Int)
        case valid(RecurrenceEndMatch)
    }

    private struct RecurrenceMatches {
        var valid: [QuickAddRecurrenceMatch] = []
        var invalid: [QuickAddInvalidRecurrenceMatch] = []
    }

    private static let recurrenceCountUnits = [
        "time",
        "times",
        "occurrence",
        "occurrences"
    ]

    private static let trailingURLPunctuation: Set<Character> = [".", ",", ";", ":", "!"]
    private static let markdownTrailingURLPunctuation = trailingURLPunctuation.union(["?"])
    private static let leadingURLDelimiters: Set<Character> = ["(", "[", "{"]
    private static let closingURLDelimiters: [Character: Character] = [")": "(", "]": "[", "}": "{"]

    private static let businessDays: [ReminderWeekday] = [
        .monday,
        .tuesday,
        .wednesday,
        .thursday,
        .friday
    ]

    static func parse(
        tokens: [QuickAddScannedToken],
        calendar: Calendar,
        now: Date
    ) -> QuickAddReminderMetadataMatches {
        let contentTokens = Array(tokens.prefix { !$0.text.hasPrefix("//") })
        let earlyReminders = earlyReminderMatches(in: contentTokens)
        let urls = urlMatches(in: contentTokens)
        let recurrences = recurrenceMatches(
            in: contentTokens,
            earlyReminders: earlyReminders,
            urls: urls,
            calendar: calendar,
            now: now
        )

        return QuickAddReminderMetadataMatches(
            recurrences: recurrences.valid,
            invalidRecurrences: recurrences.invalid,
            earlyReminders: earlyReminders,
            urls: urls
        )
    }

    private static func earlyReminderMatches(
        in tokens: [QuickAddScannedToken]
    ) -> [QuickAddEarlyReminderMatch] {
        var matches: [QuickAddEarlyReminderMatch] = []

        for index in tokens.indices where normalizedToken(at: index, in: tokens) == "remind" {
            var durationIndex = index + 1

            if normalizedToken(at: durationIndex, in: tokens) == "me" {
                durationIndex += 1
            }

            guard let duration = earlyReminderDuration(at: durationIndex, in: tokens),
                  let suffix = normalizedToken(at: duration.endIndex + 1, in: tokens),
                  suffix == "early" || suffix == "before" else {
                continue
            }

            let endIndex = duration.endIndex + 1
            matches.append(QuickAddEarlyReminderMatch(
                earlyReminder: ReminderEarlyReminder(
                    amount: duration.amount,
                    unit: duration.unit
                ),
                range: QuickAddParsingSupport.union(tokens[index].range, tokens[endIndex].range),
                startIndex: index,
                endIndex: endIndex
            ))
        }

        return matches
    }

    private static func earlyReminderDuration(
        at index: Int,
        in tokens: [QuickAddScannedToken]
    ) -> (amount: Int, unit: ReminderEarlyReminder.Unit, endIndex: Int)? {
        guard let value = normalizedToken(at: index, in: tokens) else {
            return nil
        }

        let digits = value.prefix { $0.isNumber }

        if !digits.isEmpty,
           let amount = Int(digits),
           amount > 0 {
            let suffix = String(value.dropFirst(digits.count))

            if !suffix.isEmpty,
               let unit = earlyReminderUnit(for: suffix) {
                return (amount, unit, index)
            }

            if suffix.isEmpty,
               let unitToken = normalizedToken(at: index + 1, in: tokens),
               let unit = earlyReminderUnit(for: unitToken) {
                return (amount, unit, index + 1)
            }
        }

        return nil
    }

    private static func earlyReminderUnit(for token: String) -> ReminderEarlyReminder.Unit? {
        switch token {
        case "m", "min", "mins", "minute", "minutes":
            return .minutes
        case "h", "hr", "hrs", "hour", "hours":
            return .hours
        case "d", "day", "days":
            return .days
        case "w", "wk", "wks", "week", "weeks":
            return .weeks
        default:
            return nil
        }
    }

    private static func urlMatches(in tokens: [QuickAddScannedToken]) -> [QuickAddURLMatch] {
        var matches: [QuickAddURLMatch] = []

        for (index, token) in tokens.enumerated() {
            let markdownURL = markdownURLText(from: token.text)

            if markdownURL == nil,
               token.text.hasPrefix("["),
               token.text.contains("](") {
                continue
            }

            let trimmed = markdownURL ?? trimmingExternalURLPunctuation(from: token.text)

            guard let url = URL(string: trimmed.value),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https",
                  url.host?.isEmpty == false else {
                continue
            }

            matches.append(QuickAddURLMatch(
                url: url,
                range: NSRange(
                    location: token.range.location + trimmed.leadingUTF16Length,
                    length: trimmed.usedUTF16Length
                ),
                index: index
            ))
        }

        return matches
    }

    /// Extracts the destination from a single-token Markdown link without merging both URLs.
    private static func markdownURLText(from text: String) -> TrimmedURLText? {
        guard text.first == "[",
              let separator = text.range(of: "]("),
              separator.upperBound < text.endIndex else {
            return nil
        }

        var index = separator.upperBound
        var nestedParentheses = 0

        while index < text.endIndex {
            let character = text[index]

            if character == "(" {
                nestedParentheses += 1
            } else if character == ")" {
                if nestedParentheses > 0 {
                    nestedParentheses -= 1
                } else {
                    let suffixStart = text.index(after: index)
                    let suffix = String(text[suffixStart...])

                    guard suffix.isEmpty || isExternalMarkdownURLPunctuation(suffix) else {
                        return nil
                    }

                    let value = String(text[separator.upperBound..<index])
                    guard !value.isEmpty else {
                        return nil
                    }

                    let syntaxEnd = text.index(after: index)
                    return TrimmedURLText(
                        value: value,
                        leadingUTF16Length: 0,
                        usedUTF16Length: text[..<syntaxEnd].utf16.count
                    )
                }
            }

            index = text.index(after: index)
        }

        return nil
    }

    private static func trimmingExternalURLPunctuation(from text: String) -> TrimmedURLText {
        var result = text
        var leadingUTF16Length = 0

        while let first = result.first, leadingURLDelimiters.contains(first) {
            leadingUTF16Length += String(first).utf16.count
            result.removeFirst()
        }

        while let last = result.last {
            if trailingURLPunctuation.contains(last) {
                result.removeLast()
                continue
            }

            if let opening = closingURLDelimiters[last],
               characterCount(last, in: result) > characterCount(opening, in: result) {
                result.removeLast()
                continue
            }

            break
        }

        return TrimmedURLText(
            value: result,
            leadingUTF16Length: leadingUTF16Length,
            usedUTF16Length: result.utf16.count
        )
    }

    private static func characterCount(_ character: Character, in text: String) -> Int {
        text.lazy.filter { $0 == character }.count
    }

    static func isExternalURLPunctuation(_ text: String) -> Bool {
        text.allSatisfy { character in
            markdownTrailingURLPunctuation.contains(character) ||
                closingURLDelimiters[character] != nil
        }
    }

    private static func isExternalMarkdownURLPunctuation(_ text: String) -> Bool {
        text.allSatisfy { character in
            markdownTrailingURLPunctuation.contains(character) ||
                closingURLDelimiters[character] != nil
        }
    }

    private static func recurrenceMatches(
        in tokens: [QuickAddScannedToken],
        earlyReminders: [QuickAddEarlyReminderMatch],
        urls: [QuickAddURLMatch],
        calendar: Calendar,
        now: Date
    ) -> RecurrenceMatches {
        var matches = RecurrenceMatches()

        for index in tokens.indices where normalizedToken(at: index, in: tokens) == "every" {
            guard let pattern = recurrencePattern(after: index, in: tokens) else {
                if let endIndex = invalidRecurrencePatternEnd(after: index, in: tokens) ??
                    unsupportedRecurrencePatternEnd(after: index, in: tokens) {
                    matches.invalid.append(QuickAddInvalidRecurrenceMatch(
                        startIndex: index,
                        endIndex: tokens.indices.last ?? endIndex
                    ))
                }
                continue
            }

            if hasUnsupportedRecurrenceContinuation(
                after: pattern.endIndex,
                in: tokens,
                earlyReminders: earlyReminders,
                urls: urls
            ) {
                matches.invalid.append(QuickAddInvalidRecurrenceMatch(
                    startIndex: index,
                    endIndex: tokens.indices.last ?? pattern.endIndex
                ))
                continue
            }

            guard let dueDateWithoutTime = dueDateComponents(
                for: pattern.anchor,
                time: nil,
                calendar: calendar,
                now: now
            ) else {
                matches.invalid.append(QuickAddInvalidRecurrenceMatch(
                    startIndex: index,
                    endIndex: tokens.indices.last ?? pattern.endIndex
                ))
                continue
            }

            var timeMatch = followingTime(
                after: pattern.endIndex,
                in: tokens,
                earlyReminders: earlyReminders,
                urls: urls
            )
            let endSearchAnchor = timeMatch?.endIndex ?? pattern.endIndex
            let endKeywordIndex = recurrenceEndKeywordIndex(
                after: endSearchAnchor,
                earlyReminders: earlyReminders,
                urls: urls,
                tokens: tokens
            )
            let initialEndResult = recurrenceEnd(
                at: endKeywordIndex,
                in: tokens,
                dueDate: dueDateWithoutTime,
                calendar: calendar
            )
            var endMatch: RecurrenceEndMatch?

            switch initialEndResult {
            case .absent:
                endMatch = nil
            case let .invalid(endIndex):
                matches.invalid.append(QuickAddInvalidRecurrenceMatch(
                    startIndex: index,
                    endIndex: tokens.indices.last ?? endIndex
                ))
                continue
            case let .valid(match):
                endMatch = match
            }

            if timeMatch == nil, let endMatch {
                timeMatch = followingTime(
                    after: endMatch.endIndex,
                    in: tokens,
                    earlyReminders: earlyReminders,
                    urls: urls
                )
            }

            guard let dueDate = dueDateComponents(
                for: pattern.anchor,
                time: timeMatch?.time,
                calendar: calendar,
                now: now
            ) else {
                matches.invalid.append(QuickAddInvalidRecurrenceMatch(
                    startIndex: index,
                    endIndex: tokens.indices.last ?? timeMatch?.endIndex ?? pattern.endIndex
                ))
                continue
            }

            if endMatch != nil {
                switch recurrenceEnd(
                    at: endKeywordIndex,
                    in: tokens,
                    dueDate: dueDate,
                    calendar: calendar
                ) {
                case .absent:
                    endMatch = nil
                case let .invalid(endIndex):
                    matches.invalid.append(QuickAddInvalidRecurrenceMatch(
                        startIndex: index,
                        endIndex: tokens.indices.last ?? endIndex
                    ))
                    continue
                case let .valid(match):
                    endMatch = match
                }
            }

            let recurrenceClauseEndIndex = max(
                pattern.endIndex,
                max(
                    timeMatch?.endIndex ?? pattern.endIndex,
                    endMatch?.endIndex ?? pattern.endIndex
                )
            )
            if hasUnsupportedRecurrenceContinuation(
                after: recurrenceClauseEndIndex,
                in: tokens,
                earlyReminders: earlyReminders,
                urls: urls
            ) {
                matches.invalid.append(QuickAddInvalidRecurrenceMatch(
                    startIndex: index,
                    endIndex: tokens.indices.last ?? recurrenceClauseEndIndex
                ))
                continue
            }

            let recurrence = ReminderRecurrence(
                frequency: pattern.recurrence.frequency,
                interval: pattern.recurrence.interval,
                weekdays: pattern.recurrence.weekdays,
                end: endMatch?.value
            )

            if case let .occurrenceCount(count) = recurrence.end,
               ReminderRecurrenceCalculator.finalOccurrenceEndDate(
                startingAt: dueDate,
                recurrence: recurrence,
                occurrenceCount: count
               ) == nil {
                matches.invalid.append(QuickAddInvalidRecurrenceMatch(
                    startIndex: index,
                    endIndex: tokens.indices.last ?? endMatch?.endIndex ??
                        timeMatch?.endIndex ?? pattern.endIndex
                ))
                continue
            }

            let recurrenceTokens = recurrenceTokenMatches(
                startIndex: index,
                patternEndIndex: pattern.endIndex,
                timeMatch: timeMatch,
                endMatch: endMatch,
                in: tokens
            )
            guard let primaryToken = recurrenceTokens.first else {
                continue
            }

            matches.valid.append(QuickAddRecurrenceMatch(
                recurrence: recurrence,
                dueDate: dueDate,
                dueDateWithoutTime: dueDateWithoutTime,
                range: primaryToken.range,
                startIndex: primaryToken.startIndex,
                endIndex: primaryToken.endIndex,
                detachedTokens: Array(recurrenceTokens.dropFirst())
            ))
        }

        return matches
    }

    private static func recurrenceEnd(
        at keywordIndex: Int,
        in tokens: [QuickAddScannedToken],
        dueDate: DateComponents,
        calendar: Calendar
    ) -> RecurrenceEndResult {
        switch normalizedToken(at: keywordIndex, in: tokens) {
        case "until":
            let dateIndex = keywordIndex + 1

            guard let firstOccurrence = calendar.date(from: dueDate),
                  let date = QuickAddParsingSupport.parseCalendarDate(
                at: dateIndex,
                in: tokens,
                calendar: calendar,
                relativeTo: firstOccurrence
            ), recurrenceEndDate(date.components, includes: dueDate, calendar: calendar) else {
                return .invalid(endIndex: invalidRecurrenceEndIndex(
                    at: dateIndex,
                    after: keywordIndex,
                    in: tokens
                ))
            }

            return .valid(RecurrenceEndMatch(
                value: .date(date.components),
                startIndex: keywordIndex,
                endIndex: date.endIndex
            ))
        case "for":
            let countIndex = keywordIndex + 1
            let unitIndex = keywordIndex + 2

            guard let unit = normalizedToken(at: unitIndex, in: tokens),
                  recurrenceCountUnits.contains(unit) else {
                return .absent
            }

            guard let countToken = normalizedToken(at: countIndex, in: tokens),
                  let count = Int(countToken),
                  count > 0,
                  count <= ReminderRecurrenceEnd.maximumOccurrenceCount else {
                return .invalid(endIndex: unitIndex)
            }

            return .valid(RecurrenceEndMatch(
                value: .occurrenceCount(count),
                startIndex: keywordIndex,
                endIndex: unitIndex
            ))
        default:
            return .absent
        }
    }

    /// End-repeat may follow supported metadata without making that metadata part of the recurrence token.
    private static func recurrenceEndKeywordIndex(
        after scheduleEndIndex: Int,
        earlyReminders: [QuickAddEarlyReminderMatch],
        urls: [QuickAddURLMatch],
        tokens: [QuickAddScannedToken]
    ) -> Int {
        var index = scheduleEndIndex + 1

        while true {
            if let earlyReminder = earlyReminders.first(where: { $0.startIndex == index }) {
                index = earlyReminder.endIndex + 1
                continue
            }

            if urls.contains(where: { $0.index == index }) {
                index += 1
                continue
            }

            if tokens.indices.contains(index),
               QuickAddParsingSupport.isSingleTokenReminderMetadata(tokens[index]) {
                index += 1
                continue
            }

            return index
        }
    }

    private static func recurrenceEndDate(
        _ endDate: DateComponents,
        includes dueDate: DateComponents,
        calendar: Calendar
    ) -> Bool {
        guard let end = calendar.date(from: endDate),
              let firstOccurrence = calendar.date(from: dueDate) else {
            return false
        }

        return calendar.startOfDay(for: end) >= calendar.startOfDay(for: firstOccurrence)
    }

    private static func recurrencePattern(
        after everyIndex: Int,
        in tokens: [QuickAddScannedToken]
    ) -> RecurrencePattern? {
        let valueIndex = everyIndex + 1

        guard let value = normalizedToken(at: valueIndex, in: tokens) else {
            return nil
        }

        switch value {
        case "day":
            return RecurrencePattern(
                recurrence: ReminderRecurrence(frequency: .daily),
                anchor: .today,
                endIndex: valueIndex
            )
        case "weekday", "weekdays":
            return RecurrencePattern(
                recurrence: ReminderRecurrence(frequency: .weekly, weekdays: businessDays),
                anchor: .nextBusinessDay,
                endIndex: valueIndex
            )
        default:
            break
        }

        if let weekday = QuickAddParsingSupport.weekday(for: value) {
            return RecurrencePattern(
                recurrence: ReminderRecurrence(frequency: .weekly, weekdays: [weekday]),
                anchor: .nextWeekday(weekday),
                endIndex: valueIndex
            )
        }

        if let interval = Int(value), ReminderRecurrence.supports(interval: interval),
           let unit = normalizedToken(at: valueIndex + 1, in: tokens),
           let pattern = intervalPattern(interval: interval, unit: unit, endIndex: valueIndex + 1) {
            return pattern
        }

        return intervalPattern(interval: 1, unit: value, endIndex: valueIndex)
    }

    private static func invalidRecurrencePatternEnd(
        after everyIndex: Int,
        in tokens: [QuickAddScannedToken]
    ) -> Int? {
        let intervalIndex = everyIndex + 1
        let unitIndex = everyIndex + 2

        guard let intervalToken = normalizedToken(at: intervalIndex, in: tokens),
              !intervalToken.isEmpty,
              intervalToken.allSatisfy(\.isNumber),
              let unit = normalizedToken(at: unitIndex, in: tokens),
              intervalPattern(interval: 1, unit: unit, endIndex: unitIndex) != nil else {
            return nil
        }

        return unitIndex
    }

    private static func unsupportedRecurrencePatternEnd(
        after everyIndex: Int,
        in tokens: [QuickAddScannedToken]
    ) -> Int? {
        let valueIndex = everyIndex + 1
        guard let value = normalizedToken(at: valueIndex, in: tokens), !value.isEmpty else {
            return nil
        }

        // Once "every" starts a recurrence-shaped clause, unsupported grammar stays literal.
        return valueIndex
    }

    private static func invalidRecurrenceEndIndex(
        at dateIndex: Int,
        after keywordIndex: Int,
        in tokens: [QuickAddScannedToken]
    ) -> Int {
        if let syntaxEndIndex = QuickAddParsingSupport.calendarDateSyntaxEndIndex(
            at: dateIndex,
            in: tokens
        ) {
            return syntaxEndIndex
        }

        guard let value = normalizedToken(at: dateIndex, in: tokens) else {
            return keywordIndex
        }

        if value == "today" || value == "tomorrow" || value == "tmr" || value == "tom" ||
            value.firstMatch(of: /^\d{1,2}\/\d{1,2}(?:\/(?:\d{2}|\d{4}))?$/) != nil {
            return dateIndex
        }

        if value == "next",
           QuickAddParsingSupport.weekday(for: normalizedToken(at: dateIndex + 1, in: tokens) ?? "") != nil {
            return dateIndex + 1
        }

        return keywordIndex
    }

    private static func intervalPattern(
        interval: Int,
        unit: String,
        endIndex: Int
    ) -> RecurrencePattern? {
        switch unit {
        case "day", "days":
            return RecurrencePattern(
                recurrence: ReminderRecurrence(frequency: .daily, interval: interval),
                anchor: .offset(.day, interval),
                endIndex: endIndex
            )
        case "week", "weeks":
            return RecurrencePattern(
                recurrence: ReminderRecurrence(frequency: .weekly, interval: interval),
                anchor: .offset(.weekOfYear, interval),
                endIndex: endIndex
            )
        case "month", "months":
            return RecurrencePattern(
                recurrence: ReminderRecurrence(frequency: .monthly, interval: interval),
                anchor: .offset(.month, interval),
                endIndex: endIndex
            )
        case "year", "years":
            return RecurrencePattern(
                recurrence: ReminderRecurrence(frequency: .yearly, interval: interval),
                anchor: .offset(.year, interval),
                endIndex: endIndex
            )
        default:
            return nil
        }
    }

    private static func followingTime(
        after index: Int,
        in tokens: [QuickAddScannedToken],
        earlyReminders: [QuickAddEarlyReminderMatch] = [],
        urls: [QuickAddURLMatch] = []
    ) -> RecurrenceTimeMatch? {
        let atIndex = indexAfterMetadata(
            after: index,
            in: tokens,
            earlyReminders: earlyReminders,
            urls: urls
        )
        let timeIndex = atIndex + 1

        guard normalizedToken(at: atIndex, in: tokens) == "at",
              tokens.indices.contains(timeIndex),
              let time = QuickAddParsingSupport.parseTime(tokens[timeIndex].text) else {
            return nil
        }

        return RecurrenceTimeMatch(time: time, startIndex: atIndex, endIndex: timeIndex)
    }

    private static func indexAfterMetadata(
        after index: Int,
        in tokens: [QuickAddScannedToken],
        earlyReminders: [QuickAddEarlyReminderMatch],
        urls: [QuickAddURLMatch]
    ) -> Int {
        var nextIndex = index + 1

        while true {
            if let earlyReminder = earlyReminders.first(where: { $0.startIndex == nextIndex }) {
                nextIndex = earlyReminder.endIndex + 1
                continue
            }

            if urls.contains(where: { $0.index == nextIndex }) {
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

    private static func hasUnsupportedRecurrenceContinuation(
        after recurrenceClauseEndIndex: Int,
        in tokens: [QuickAddScannedToken],
        earlyReminders: [QuickAddEarlyReminderMatch],
        urls: [QuickAddURLMatch]
    ) -> Bool {
        let nextIndex = indexAfterMetadata(
            after: recurrenceClauseEndIndex,
            in: tokens,
            earlyReminders: earlyReminders,
            urls: urls
        )
        guard let next = normalizedToken(at: nextIndex, in: tokens) else {
            return false
        }

        return next == "and" || next == "or"
    }

    private static func recurrenceTokenMatches(
        startIndex: Int,
        patternEndIndex: Int,
        timeMatch: RecurrenceTimeMatch?,
        endMatch: RecurrenceEndMatch?,
        in tokens: [QuickAddScannedToken]
    ) -> [QuickAddRecurrenceTokenMatch] {
        var spans = [RecurrenceTokenSpan(
            startIndex: startIndex,
            endIndex: patternEndIndex,
            includesTime: false,
            includesEnd: false
        )]

        if let timeMatch {
            appendRecurrenceSpan(
                startIndex: timeMatch.startIndex,
                endIndex: timeMatch.endIndex,
                includesTime: true,
                includesEnd: false,
                to: &spans
            )
        }

        if let endMatch {
            appendRecurrenceSpan(
                startIndex: endMatch.startIndex,
                endIndex: endMatch.endIndex,
                includesTime: false,
                includesEnd: true,
                to: &spans
            )
        }

        return spans.sorted { $0.startIndex < $1.startIndex }.map { span in
            QuickAddRecurrenceTokenMatch(
                range: QuickAddParsingSupport.union(
                    tokens[span.startIndex].range,
                    tokens[span.endIndex].range
                ),
                startIndex: span.startIndex,
                endIndex: span.endIndex,
                includesTime: span.includesTime,
                includesEnd: span.includesEnd
            )
        }
    }

    private static func appendRecurrenceSpan(
        startIndex: Int,
        endIndex: Int,
        includesTime: Bool,
        includesEnd: Bool,
        to spans: inout [RecurrenceTokenSpan]
    ) {
        if let index = spans.firstIndex(where: {
            startIndex <= $0.endIndex + 1 && endIndex >= $0.startIndex - 1
        }) {
            spans[index].startIndex = min(spans[index].startIndex, startIndex)
            spans[index].endIndex = max(spans[index].endIndex, endIndex)
            spans[index].includesTime = spans[index].includesTime || includesTime
            spans[index].includesEnd = spans[index].includesEnd || includesEnd
        } else {
            spans.append(RecurrenceTokenSpan(
                startIndex: startIndex,
                endIndex: endIndex,
                includesTime: includesTime,
                includesEnd: includesEnd
            ))
        }
    }

    private static func dueDateComponents(
        for anchor: RecurrenceAnchor,
        time: QuickAddParsedTime?,
        calendar: Calendar,
        now: Date
    ) -> DateComponents? {
        let date: Date?

        switch anchor {
        case .today:
            date = nextOccurrence(
                onOrAfter: calendar.startOfDay(for: now),
                allowedWeekdays: nil,
                time: time,
                calendar: calendar,
                now: now
            )
        case let .nextWeekday(weekday):
            date = nextOccurrence(
                onOrAfter: calendar.startOfDay(for: now),
                allowedWeekdays: [weekday],
                time: time,
                calendar: calendar,
                now: now
            )
        case .nextBusinessDay:
            date = nextOccurrence(
                onOrAfter: calendar.startOfDay(for: now),
                allowedWeekdays: businessDays,
                time: time,
                calendar: calendar,
                now: now
            )
        case let .offset(component, value):
            if let time {
                return nextTimedOffsetOccurrence(
                    component: component,
                    interval: value,
                    time: time,
                    after: now,
                    calendar: calendar
                )
            }

            date = nextValidCalendarUnitOccurrence(
                component: component,
                interval: value,
                after: now,
                calendar: calendar
            )
        }

        guard let date else {
            return nil
        }

        let components = calendar.dateComponents(
            [.calendar, .timeZone, .year, .month, .day],
            from: date
        )

        guard let time else {
            return components
        }

        return QuickAddParsingSupport.applying(time, to: components, calendar: calendar)
    }

    private static func nextTimedOffsetOccurrence(
        component: Calendar.Component,
        interval: Int,
        time: QuickAddParsedTime,
        after now: Date,
        calendar: Calendar
    ) -> DateComponents? {
        for cycle in 1...4800 {
            let multiplied = interval.multipliedReportingOverflow(by: cycle)
            guard !multiplied.overflow,
                  let date = exactCalendarUnitOccurrence(
                    component: component,
                    value: multiplied.partialValue,
                    after: now,
                    calendar: calendar
                  ) else {
                continue
            }

            let dateComponents = calendar.dateComponents(
                [.calendar, .timeZone, .year, .month, .day],
                from: date
            )
            if let components = QuickAddParsingSupport.applyingExact(
                time,
                to: dateComponents,
                calendar: calendar
            ) {
                return components
            }
        }

        return nil
    }

    private static func nextValidCalendarUnitOccurrence(
        component: Calendar.Component,
        interval: Int,
        after now: Date,
        calendar: Calendar
    ) -> Date? {
        guard component == .month || component == .year else {
            return calendar.date(byAdding: component, value: interval, to: now)
        }

        for cycle in 1...4800 {
            let multiplied = interval.multipliedReportingOverflow(by: cycle)
            guard !multiplied.overflow else {
                return nil
            }

            if let date = exactCalendarUnitOccurrence(
                component: component,
                value: multiplied.partialValue,
                after: now,
                calendar: calendar
            ) {
                return date
            }
        }

        return nil
    }

    private static func exactCalendarUnitOccurrence(
        component: Calendar.Component,
        value: Int,
        after now: Date,
        calendar: Calendar
    ) -> Date? {
        guard component == .month || component == .year else {
            return calendar.date(byAdding: component, value: value, to: now)
        }

        let preserved = calendar.dateComponents(
            [.month, .day, .hour, .minute, .second, .nanosecond],
            from: now
        )
        let base = calendar.dateComponents([.year, .month], from: now)
        var unitAnchor = base
        unitAnchor.calendar = calendar
        unitAnchor.timeZone = calendar.timeZone
        unitAnchor.day = 1

        guard let anchorDate = calendar.date(from: unitAnchor) else {
            return nil
        }

        guard let advanced = calendar.date(
            byAdding: component,
            value: value,
            to: anchorDate
        ) else {
            return nil
        }

        let advancedUnit = calendar.dateComponents([.year, .month], from: advanced)
        var candidate = preserved
        candidate.calendar = calendar
        candidate.timeZone = calendar.timeZone
        candidate.year = advancedUnit.year
        candidate.month = component == .year ? preserved.month : advancedUnit.month

        guard let date = calendar.date(from: candidate),
              calendar.component(.year, from: date) == candidate.year,
              calendar.component(.month, from: date) == candidate.month,
              calendar.component(.day, from: date) == preserved.day else {
            return nil
        }

        return date
    }

    private static func nextOccurrence(
        onOrAfter startDate: Date,
        allowedWeekdays: [ReminderWeekday]?,
        time: QuickAddParsedTime?,
        calendar: Calendar,
        now: Date
    ) -> Date? {
        for dayOffset in 0...7 {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: startDate) else {
                continue
            }

            if let allowedWeekdays,
               !allowedWeekdays.contains(where: { $0.rawValue == calendar.component(.weekday, from: date) }) {
                continue
            }

            guard let time else {
                return date
            }

            let components = calendar.dateComponents(
                [.calendar, .timeZone, .year, .month, .day],
                from: date
            )

            if let resolvedComponents = QuickAddParsingSupport.applyingExact(
                time,
                to: components,
                calendar: calendar
            ), let candidate = calendar.date(from: resolvedComponents), candidate > now {
                return candidate
            }
        }

        return nil
    }

    private static func normalizedToken(
        at index: Int,
        in tokens: [QuickAddScannedToken]
    ) -> String? {
        guard tokens.indices.contains(index) else {
            return nil
        }

        return QuickAddParsingSupport.normalized(tokens[index].text)
    }
}
