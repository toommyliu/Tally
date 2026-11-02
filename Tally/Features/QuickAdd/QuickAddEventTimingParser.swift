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

    var length: QuickAddEventDuration? {
        guard case let .length(length) = self else {
            return nil
        }

        return length
    }
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

    static func matches(in tokens: QuickAddParseWords) -> [QuickAddEventTimingMatch] {
        var matches: [QuickAddEventTimingMatch] = []
        var index = 0
        while index < tokens.count {
            guard let match = timeRange(at: index, in: tokens) ?? duration(at: index, in: tokens).map({
                (QuickAddEventTimingToken.duration($0.duration), $0.endIndex)
            }), tokens.contiguousRange(from: index, through: match.endIndex) != nil else {
                index += 1
                continue
            }
            matches.append(QuickAddEventTimingMatch(timing: match.value, startIndex: index, endIndex: match.endIndex))
            index = match.endIndex + 1
        }
        return matches
    }

    // MARK: - Time ranges

    private static func timeRange(
        at index: Int,
        in tokens: QuickAddParseWords
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
        in tokens: QuickAddParseWords
    ) -> (duration: QuickAddEventDuration, endIndex: Int)? {
        guard normalized(at: index, in: tokens) == "for",
              let first = normalized(at: index + 1, in: tokens) else {
            return nil
        }

        if let duration = QuickAddDurationParser.compactEventDuration(first) {
            return (duration, index + 1)
        }

        if first == "half",
           ["an", "a"].contains(normalized(at: index + 2, in: tokens)),
           ["hour", "hr"].contains(normalized(at: index + 3, in: tokens)) {
            return (.minutes(30), index + 3)
        }

        guard let amount = QuickAddDurationParser.spokenAmount(first),
              let unitText = normalized(at: index + 2, in: tokens),
              let duration = QuickAddDurationParser.eventDuration(amount: amount, unit: unitText) else {
            return nil
        }

        return (duration, index + 2)
    }

    private static func normalized(at index: Int, in tokens: QuickAddParseWords) -> String? {
        guard tokens.indices.contains(index) else {
            return nil
        }

        return QuickAddParsingSupport.normalized(tokens.word(at: index) ?? "")
    }
}
