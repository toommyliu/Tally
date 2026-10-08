import Foundation

/// How long an event lasts when the text gives a length instead of an end time.
struct QuickAddEventDuration: Hashable {
    enum Unit: Hashable {
        case minutes
        case days
    }

    let amount: Int
    let unit: Unit

    init(amount: Int, unit: Unit) {
        self.amount = max(amount, 1)
        self.unit = unit
    }

    static func minutes(_ amount: Int) -> QuickAddEventDuration {
        QuickAddEventDuration(amount: amount, unit: .minutes)
    }

    static func days(_ amount: Int) -> QuickAddEventDuration {
        QuickAddEventDuration(amount: amount, unit: .days)
    }

    var token: String {
        switch unit {
        case .minutes where amount % 60 == 0:
            return "for \(amount / 60)h"
        case .minutes where amount > 60:
            return "for \(amount / 60)h\(amount % 60)m"
        case .minutes:
            return "for \(amount)m"
        case .days:
            return amount == 1 ? "for 1 day" : "for \(amount) days"
        }
    }

    func end(after start: Date, calendar: Calendar) -> Date? {
        switch unit {
        case .minutes:
            return calendar.date(byAdding: .minute, value: amount, to: start)
        case .days:
            return calendar.date(byAdding: .day, value: amount, to: start)
        }
    }
}

enum QuickAddEventEnd {
    case time(QuickAddParsedTime)
    case length(QuickAddEventDuration)
}

enum QuickAddEventTimingToken {
    case timeRange(start: QuickAddParsedTime, end: QuickAddEventEnd)
    case duration(QuickAddEventDuration)
}

/// Finds time ranges (`2-3pm`, `2pm to 4pm`, `from 2 to 3pm`, `2pm for 45m`)
/// and durations (`for 45m`, `for 2 hours`) and folds each multi-word phrase
/// into one scanned token. Folding keeps the rest of the parser from reading
/// `2pm` in `2pm - 4pm` as a standalone time.
enum QuickAddEventTimingParser {
    private static let rangeSeparators: Set<String> = ["-", "–", "—", "to"]
    private static let singleTokenSeparators: [Character] = ["-", "–", "—"]

    static func parse(
        _ tokens: [QuickAddScannedToken],
        in input: String
    ) -> [QuickAddScannedToken] {
        let text = input as NSString
        var folded: [QuickAddScannedToken] = []
        var index = 0

        while index < tokens.count {
            if tokens[index].text.hasPrefix("//") {
                folded.append(contentsOf: tokens[index...])
                break
            }

            guard let match = timeRange(at: index, in: tokens) ?? duration(at: index, in: tokens).map({
                (QuickAddEventTimingToken.duration($0.duration), $0.endIndex)
            }) else {
                folded.append(tokens[index])
                index += 1
                continue
            }

            let range = QuickAddParsingSupport.union(tokens[index].range, tokens[match.endIndex].range)
            folded.append(QuickAddScannedToken(
                text: text.substring(with: range),
                range: range,
                eventTiming: match.value
            ))
            index = match.endIndex + 1
        }

        return folded
    }

    // MARK: - Time ranges

    private static func timeRange(
        at index: Int,
        in tokens: [QuickAddScannedToken]
    ) -> (value: QuickAddEventTimingToken, endIndex: Int)? {
        var startIndex = index

        if ["from", "at"].contains(normalized(at: index, in: tokens)) {
            startIndex += 1
        }

        guard let startText = normalized(at: startIndex, in: tokens) else {
            return nil
        }

        if let (start, end) = singleTokenRange(startText),
           let value = resolvedRange(start: start, end: end) {
            return (value, startIndex)
        }

        if let separator = normalized(at: startIndex + 1, in: tokens),
           rangeSeparators.contains(separator),
           let endText = normalized(at: startIndex + 2, in: tokens),
           let value = resolvedRange(start: startText, end: endText) {
            return (value, startIndex + 2)
        }

        guard let start = QuickAddParsingSupport.parseTime(startText),
              start.hasMeridiem || start.hasColon,
              let length = duration(at: startIndex + 1, in: tokens) else {
            return nil
        }

        return (.timeRange(start: start, end: .length(length.duration)), length.endIndex)
    }

    private static func singleTokenRange(_ text: String) -> (String, String)? {
        guard let separatorIndex = text.firstIndex(where: singleTokenSeparators.contains) else {
            return nil
        }

        let start = String(text[..<separatorIndex])
        let end = String(text[text.index(after: separatorIndex)...])
        guard !start.isEmpty, !end.isEmpty else {
            return nil
        }

        return (start, end)
    }

    private static func resolvedRange(
        start startText: String,
        end endText: String
    ) -> QuickAddEventTimingToken? {
        guard var start = QuickAddParsingSupport.parseTime(startText),
              var end = QuickAddParsingSupport.parseTime(endText),
              start.hasMeridiem || start.hasColon || end.hasMeridiem || end.hasColon else {
            return nil
        }

        if !start.hasMeridiem, end.hasMeridiem, (1...12).contains(start.hour) {
            start = inferringMeridiem(of: start) { forwardMinutes(from: $0, to: end) }
        } else if start.hasMeridiem, !end.hasMeridiem, (1...12).contains(end.hour) {
            end = inferringMeridiem(of: end) { forwardMinutes(from: start, to: $0) }
        }

        return .timeRange(start: start, end: .time(end))
    }

    private static func inferringMeridiem(
        of time: QuickAddParsedTime,
        duration: (QuickAddParsedTime) -> Int
    ) -> QuickAddParsedTime {
        let morning = QuickAddParsedTime(
            hour: time.hour % 12,
            minute: time.minute,
            hasMeridiem: true,
            hasColon: time.hasColon
        )
        let evening = QuickAddParsedTime(
            hour: time.hour % 12 + 12,
            minute: time.minute,
            hasMeridiem: true,
            hasColon: time.hasColon
        )

        return duration(morning) < duration(evening) ? morning : evening
    }

    private static func forwardMinutes(from start: QuickAddParsedTime, to end: QuickAddParsedTime) -> Int {
        let difference = (end.hour - start.hour) * 60 + end.minute - start.minute
        return difference > 0 ? difference : difference + 24 * 60
    }

    // MARK: - Durations

    private static func duration(
        at index: Int,
        in tokens: [QuickAddScannedToken]
    ) -> (duration: QuickAddEventDuration, endIndex: Int)? {
        guard normalized(at: index, in: tokens) == "for",
              let first = normalized(at: index + 1, in: tokens) else {
            return nil
        }

        if let duration = compactDuration(first) {
            return (duration, index + 1)
        }

        if first == "half",
           ["an", "a"].contains(normalized(at: index + 2, in: tokens)),
           ["hour", "hr"].contains(normalized(at: index + 3, in: tokens)) {
            return (.minutes(30), index + 3)
        }

        guard let amount = spokenAmount(first),
              let unitText = normalized(at: index + 2, in: tokens),
              let duration = duration(amount: amount, unit: unitText) else {
            return nil
        }

        return (duration, index + 2)
    }

    /// Single-token durations such as `45m`, `1.5h`, `1h30m`, or `2d`.
    private static func compactDuration(_ text: String) -> QuickAddEventDuration? {
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

        return duration(amount: amount, unit: String(match.2))
    }

    private static func spokenAmount(_ text: String) -> Double? {
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

    private static func duration(amount: Double, unit: String) -> QuickAddEventDuration? {
        switch unit {
        case "m", "min", "mins", "minute", "minutes":
            return positiveMinutes(amount)
        case "h", "hr", "hrs", "hour", "hours":
            return positiveMinutes(amount * 60)
        case "d", "day", "days":
            return wholeDays(amount)
        case "w", "wk", "wks", "week", "weeks":
            return wholeDays(amount * 7)
        default:
            return nil
        }
    }

    private static func positiveMinutes(_ minutes: Double) -> QuickAddEventDuration? {
        guard let amount = Int(exactly: minutes.rounded()), amount > 0 else {
            return nil
        }

        return .minutes(amount)
    }

    private static func wholeDays(_ days: Double) -> QuickAddEventDuration? {
        guard let amount = Int(exactly: days), amount > 0 else {
            return nil
        }

        return .days(amount)
    }

    private static func normalized(at index: Int, in tokens: [QuickAddScannedToken]) -> String? {
        guard tokens.indices.contains(index) else {
            return nil
        }

        return QuickAddParsingSupport.normalized(tokens[index].text)
    }
}
