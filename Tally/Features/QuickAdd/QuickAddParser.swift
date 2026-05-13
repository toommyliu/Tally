import Foundation

struct QuickAddFields: Equatable {
    var title: String
    var listName: String?
    var tags: [String]
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
    }

    var kind: Kind
    var range: NSRange
}

enum QuickAddParser {
    static func parse(
        _ input: String,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> QuickAddFields {
        var titleTokens: [String] = []
        var listName: String?
        var tags: [String] = []
        var dueDate: DateComponents?
        var priority = 0
        var usedTokens: [QuickAddToken] = []
        let tokens = scanTokens(in: input)
        var index = 0

        while index < tokens.count {
            let token = tokens[index]

            if token.text.hasPrefix("#"), token.text.count > 1 {
                listName = String(token.text.dropFirst())
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
               let parsedRelativeDate = parseRelativeDate(at: index, in: tokens, calendar: calendar, now: now) {
                dueDate = parsedRelativeDate.components
                usedTokens.append(QuickAddToken(kind: parsedRelativeDate.kind, range: parsedRelativeDate.range))
                index = parsedRelativeDate.endIndex + 1
                continue
            }

            if dueDate == nil,
               var parsedDueDate = parseDueDate(token.text, calendar: calendar, now: now) {
                usedTokens.append(QuickAddToken(kind: .date, range: token.range))

                if let nextToken = nextTimeToken(after: index, in: tokens),
                   let parsedTime = parseTime(nextToken.text) {
                    parsedDueDate.hour = parsedTime.hour
                    parsedDueDate.minute = parsedTime.minute
                    usedTokens.removeLast()
                    usedTokens.append(QuickAddToken(kind: .time, range: union(token.range, nextToken.range)))
                    index = nextToken.index + 1
                } else {
                    index += 1
                }

                dueDate = parsedDueDate
                continue
            }

            titleTokens.append(token.text)
            index += 1
        }

        return QuickAddFields(
            title: titleTokens.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines),
            listName: listName,
            tags: tags,
            dueDate: dueDate,
            priority: priority,
            usedTokens: usedTokens
        )
    }

    private struct ScannedToken {
        var text: String
        var range: NSRange
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
        case "today":
            return dateOnlyComponents(from: now, calendar: calendar)
        case "tomorrow", "tmr":
            guard let date = calendar.date(byAdding: .day, value: 1, to: now) else {
                return nil
            }
            return dateOnlyComponents(from: date, calendar: calendar)
        default:
            return nil
        }
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
           let amountToken = normalizedToken(at: index + 1, in: tokens),
           let amount = parseRelativeAmount(amountToken),
           amount > 0,
           let unitToken = normalizedToken(at: index + 2, in: tokens),
           let unit = RelativeUnit(unitToken) {
            return relativeDuration(
                amount: amount,
                unit: unit,
                from: now,
                range: union(tokens[index].range, tokens[index + 2].range),
                endIndex: index + 2,
                calendar: calendar
            )
        }

        if normalized == "in",
           let compactToken = normalizedToken(at: index + 1, in: tokens),
           let compactDuration = parseCompactDuration(compactToken),
           compactDuration.amount > 0 {
            return relativeDuration(
                amount: compactDuration.amount,
                unit: compactDuration.unit,
                from: now,
                range: union(tokens[index].range, tokens[index + 1].range),
                endIndex: index + 1,
                calendar: calendar
            )
        }

        return nil
    }

    private static func parseRelativeAmount(_ token: String) -> Int? {
        switch token {
        case "a", "an", "one":
            return 1
        default:
            return Int(token)
        }
    }

    private static func parseCompactDuration(_ token: String) -> (amount: Int, unit: RelativeUnit)? {
        guard let match = token.firstMatch(of: /^(\d+)(m|mins?|h|hrs?|d|w)$/),
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

    private static func nextTimeToken(
        after index: Int,
        in tokens: [ScannedToken]
    ) -> (index: Int, text: String, range: NSRange)? {
        let nextIndex = index + 1

        guard nextIndex < tokens.count else {
            return nil
        }

        if tokens[nextIndex].text.lowercased() == "at" {
            let timeIndex = nextIndex + 1

            guard timeIndex < tokens.count else {
                return nil
            }

            return (timeIndex, tokens[timeIndex].text, tokens[timeIndex].range)
        }

        return (nextIndex, tokens[nextIndex].text, tokens[nextIndex].range)
    }

    private static func union(_ lhs: NSRange, _ rhs: NSRange) -> NSRange {
        let start = min(lhs.location, rhs.location)
        let end = max(NSMaxRange(lhs), NSMaxRange(rhs))
        return NSRange(location: start, length: end - start)
    }

    private static func parseTime(_ token: String) -> (hour: Int, minute: Int)? {
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

        return (hour, minute)
    }

    private static func dateOnlyComponents(from date: Date, calendar: Calendar) -> DateComponents {
        calendar.dateComponents([.calendar, .timeZone, .year, .month, .day], from: date)
    }

    private static func dateAndTimeComponents(from date: Date, calendar: Calendar) -> DateComponents {
        calendar.dateComponents([.calendar, .timeZone, .year, .month, .day, .hour, .minute], from: date)
    }
}
