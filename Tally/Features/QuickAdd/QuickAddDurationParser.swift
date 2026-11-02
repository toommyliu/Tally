import Foundation

enum QuickAddDurationParser {

    static func unit(_ text: String) -> ScheduleUnit? {
        switch text {
        case "m", "min", "mins", "minute", "minutes": .minutes
        case "h", "hr", "hrs", "hour", "hours": .hours
        case "d", "day", "days": .days
        case "w", "wk", "wks", "week", "weeks": .weeks
        case "mo", "mos", "month", "months": .months
        default: nil
        }
    }

    struct RelativeDurationMatch {
        var amount: Int
        var unit: RelativeUnit
        var endIndex: Int
    }

    enum RelativeUnit {
        case minute
        case hour
        case day
        case week

        init?(_ token: String) {
            switch QuickAddDurationParser.unit(token) {
            case .minutes: self = .minute
            case .hours: self = .hour
            case .days: self = .day
            case .weeks where !["wk", "wks"].contains(token): self = .week
            default: return nil
            }
        }
    }

    static func parseRelativeAmount(_ token: String) -> Int? {
        let normalized = token.hasPrefix("+") ? String(token.dropFirst()) : token

        switch normalized {
        case "a", "an", "one":
            return 1
        default:
            return Int(normalized)
        }
    }

    static func parseRelativeDurationPhrase(
        at index: Int,
        in tokens: QuickAddParseWords
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

    static func halfDuration(for unit: RelativeUnit, endIndex: Int) -> RelativeDurationMatch? {
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

    static func parseRelativeAmountExpression(
        at index: Int,
        in tokens: QuickAddParseWords
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

    static func parseFuzzyRelativeAmount(_ token: String) -> Int? {
        switch token {
        case "couple":
            return 2
        case "few":
            return 3
        default:
            return nil
        }
    }

    static func optionalOfEndIndex(after index: Int, in tokens: QuickAddParseWords) -> Int {
        normalizedToken(at: index + 1, in: tokens) == "of" ? index + 1 : index
    }

    static func parseSpelledNumber(
        at index: Int,
        in tokens: QuickAddParseWords
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

    static func spelledNumberValue(_ token: String) -> Int? {
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

    static func parseCompactDuration(_ token: String) -> (amount: Int, unit: RelativeUnit)? {
        guard let match = token.firstMatch(of: /^\+?(\d+)(m|mins?|h|hrs?|d|w)$/),
              let amount = Int(match.1),
              let unit = RelativeUnit(String(match.2)) else {
            return nil
        }

        return (amount, unit)
    }

    static func compactEventDuration(_ text: String) -> QuickAddEventDuration? {
        if let match = text.firstMatch(of: /^(\d{1,2})h(\d{1,2})m?$/),
           let hours = Int(match.1),
           let minutes = Int(match.2),
           minutes < 60 {
            return positiveMinutes(Double(hours * 60 + minutes))
        }

        guard let match = text.firstMatch(of: /^(\d+(?:\.\d+)?)([a-z]+)$/),
              let amount = Double(match.1) else {
            return nil
        }

        return eventDuration(amount: amount, unit: String(match.2))
    }

    static func spokenAmount(_ text: String) -> Double? {
        switch text {
        case "a", "an", "one":
            return 1
        case "two":
            return 2
        case "three":
            return 3
        default:
            return Double(text)
        }
    }

    static func eventDuration(amount: Double, unit: String) -> QuickAddEventDuration? {
        switch Self.unit(unit) {
        case .minutes: return positiveMinutes(amount)
        case .hours: return positiveMinutes(amount * 60)
        case .days: return wholeDays(amount)
        case .weeks: return wholeDays(amount * 7)
        default: return nil
        }
    }


    static func positiveMinutes(_ minutes: Double) -> QuickAddEventDuration? {
        guard let amount = Int(exactly: minutes.rounded()), amount > 0 else {
            return nil
        }

        return .minutes(amount)
    }

    static func wholeDays(_ days: Double) -> QuickAddEventDuration? {
        guard let amount = Int(exactly: days), amount > 0 else {
            return nil
        }

        return .days(amount)
    }

    private static func normalizedToken(at index: Int, in tokens: QuickAddParseWords) -> String? {
        tokens.normalized(at: index)
    }
}
