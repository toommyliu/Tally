import Foundation

/// A whitespace-delimited token and its UTF-16 range in the original Quick Add text.
struct QuickAddScannedToken {
    let text: String
    let range: NSRange
    var eventTiming: QuickAddEventTimingToken? = nil
}

/// A parsed wall-clock time used by both one-off and recurring schedule parsing.
struct QuickAddParsedTime {
    let hour: Int
    let minute: Int
    let hasMeridiem: Bool
    let hasColon: Bool
}

/// A concrete calendar date parsed from explicit or named date language.
struct QuickAddCalendarDateMatch {
    let components: DateComponents
    let range: NSRange
    let endIndex: Int
    let isExplicit: Bool
}

enum QuickAddParsingSupport {
    private static let sentencePunctuation = CharacterSet(charactersIn: ".,;!?")

    static func scanTokens(in input: String) -> [QuickAddScannedToken] {
        var tokens: [QuickAddScannedToken] = []
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
            let location = input.utf16.distance(
                from: input.utf16.startIndex,
                to: start.samePosition(in: input.utf16)!
            )
            tokens.append(QuickAddScannedToken(
                text: text,
                range: NSRange(location: location, length: text.utf16.count)
            ))
        }

        return tokens
    }

    static func normalized(_ token: String) -> String {
        trimmingSentencePunctuation(from: token).lowercased()
    }

    static func trimmingSentencePunctuation(from token: String) -> String {
        token.trimmingCharacters(in: sentencePunctuation)
    }

    static func prefixedMetadataValue(_ prefix: Character, in token: String) -> String? {
        let trimmed = trimmingSentencePunctuation(from: token)
        guard trimmed.first == prefix, trimmed.count > 1 else {
            return nil
        }

        return String(trimmed.dropFirst())
    }

    static func priority(for token: String) -> Int? {
        switch normalized(token) {
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

    /// Returns whether one scanned token is independently parsed reminder metadata.
    static func isSingleTokenReminderMetadata(_ text: String) -> Bool {
        prefixedMetadataValue("#", in: text) != nil ||
            trimmingSentencePunctuation(from: text) == "@" ||
            prefixedMetadataValue("@", in: text) != nil ||
            priority(for: text) != nil
    }

    static func parseTime(_ token: String) -> QuickAddParsedTime? {
        let normalized = normalized(token)

        guard let match = normalized.firstMatch(of: /^(\d{1,2})(?::(\d{2}))?(am|pm)?$/),
              var hour = Int(match.1) else {
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

        return QuickAddParsedTime(
            hour: hour,
            minute: minute,
            hasMeridiem: meridiem != nil,
            hasColon: hasColon
        )
    }

    /// Applies a wall-clock time and returns the components Foundation actually resolves.
    /// This keeps one-off and recurring reminders consistent across DST transitions.
    static func applying(
        _ time: QuickAddParsedTime,
        to dateComponents: DateComponents,
        calendar: Calendar
    ) -> DateComponents? {
        var requested = dateComponents
        requested.calendar = calendar
        requested.timeZone = calendar.timeZone
        requested.hour = time.hour
        requested.minute = time.minute

        guard let resolvedDate = calendar.date(from: requested) else {
            return nil
        }

        return calendar.dateComponents(
            [.calendar, .timeZone, .year, .month, .day, .hour, .minute],
            from: resolvedDate
        )
    }

    /// Applies a recurring wall-clock time only when that local time exists exactly.
    static func applyingExact(
        _ time: QuickAddParsedTime,
        to dateComponents: DateComponents,
        calendar: Calendar
    ) -> DateComponents? {
        guard let resolved = applying(time, to: dateComponents, calendar: calendar),
              resolved.year == dateComponents.year,
              resolved.month == dateComponents.month,
              resolved.day == dateComponents.day,
              resolved.hour == time.hour,
              resolved.minute == time.minute else {
            return nil
        }

        return resolved
    }

    static func weekday(for token: String) -> ReminderWeekday? {
        switch normalized(token) {
        case "sunday", "sun":
            return .sunday
        case "monday", "mon":
            return .monday
        case "tuesday", "tue", "tues":
            return .tuesday
        case "wednesday", "wed":
            return .wednesday
        case "thursday", "thu", "thur", "thurs":
            return .thursday
        case "friday", "fri":
            return .friday
        case "saturday", "sat":
            return .saturday
        default:
            return nil
        }
    }

    /// Parses the narrow date forms shared by due dates and recurrence endpoints.
    static func parseCalendarDate(
        at index: Int,
        in tokens: QuickAddParseWords,
        calendar: Calendar,
        relativeTo referenceDate: Date
    ) -> QuickAddCalendarDateMatch? {
        guard tokens.indices.contains(index) else {
            return nil
        }

        let first = normalized(tokens.word(at: index) ?? "")

        if let components = isoDate(first, calendar: calendar) {
            return QuickAddCalendarDateMatch(
                components: components,
                range: tokens[index].range,
                endIndex: index,
                isExplicit: true
            )
        }

        guard tokens.indices.contains(index + 1) else {
            return nil
        }

        let second = normalized(tokens.word(at: index + 1) ?? "")
        let monthAndDay: (month: Int, day: Int)?

        if let month = monthNumber(for: first), let day = dayNumber(second) {
            monthAndDay = (month, day)
        } else if let day = dayNumber(first), let month = monthNumber(for: second) {
            monthAndDay = (month, day)
        } else {
            monthAndDay = nil
        }

        guard let monthAndDay else {
            return nil
        }

        let yearIndex = index + 2
        let explicitYear = tokens.indices.contains(yearIndex)
            ? parseExplicitYear(normalized(tokens.word(at: yearIndex) ?? ""))
            : nil
        let components: DateComponents?

        if let explicitYear {
            components = dateComponents(
                year: explicitYear,
                month: monthAndDay.month,
                day: monthAndDay.day,
                calendar: calendar
            )
        } else {
            components = upcomingDate(
                month: monthAndDay.month,
                day: monthAndDay.day,
                calendar: calendar,
                referenceDate: referenceDate
            )
        }

        guard let components else {
            return nil
        }

        let endIndex = explicitYear == nil ? index + 1 : yearIndex

        return QuickAddCalendarDateMatch(
            components: components,
            range: union(tokens[index].range, tokens[endIndex].range),
            endIndex: endIndex,
            isExplicit: explicitYear != nil
        )
    }

    /// Returns the token boundary for text shaped like a calendar date, even when invalid.
    static func calendarDateSyntaxEndIndex(
        at index: Int,
        in tokens: QuickAddParseWords
    ) -> Int? {
        guard tokens.indices.contains(index) else {
            return nil
        }

        let first = normalized(tokens.word(at: index) ?? "")

        if first.firstMatch(of: /^\d{4}-\d{2}-\d{2}$/) != nil {
            return index
        }

        if monthNumber(for: first) != nil {
            guard tokens.indices.contains(index + 1) else {
                return index
            }

            guard isDaySyntax(normalized(tokens.word(at: index + 1) ?? "")) else {
                return index
            }

            return explicitYearSyntaxEndIndex(after: index + 1, in: tokens)
        }

        guard isDaySyntax(first),
              tokens.indices.contains(index + 1),
              monthNumber(for: normalized(tokens.word(at: index + 1) ?? "")) != nil else {
            return nil
        }

        return explicitYearSyntaxEndIndex(after: index + 1, in: tokens)
    }

    static func union(_ lhs: NSRange, _ rhs: NSRange) -> NSRange {
        let start = min(lhs.location, rhs.location)
        let end = max(NSMaxRange(lhs), NSMaxRange(rhs))
        return NSRange(location: start, length: end - start)
    }

    private static func isoDate(_ token: String, calendar: Calendar) -> DateComponents? {
        let parts = token.split(separator: "-", omittingEmptySubsequences: false)

        guard parts.count == 3,
              parts[0].count == 4,
              parts[1].count == 2,
              parts[2].count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return nil
        }

        return dateComponents(year: year, month: month, day: day, calendar: calendar)
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

    private static func dayNumber(_ token: String) -> Int? {
        let cleaned = token.replacing(/(st|nd|rd|th)$/, with: "")

        guard let day = Int(cleaned), (1...31).contains(day) else {
            return nil
        }

        return day
    }

    private static func isDaySyntax(_ token: String) -> Bool {
        token.firstMatch(of: /^\d{1,2}(st|nd|rd|th)?$/) != nil
    }

    private static func explicitYearSyntaxEndIndex(
        after monthAndDayEndIndex: Int,
        in tokens: QuickAddParseWords
    ) -> Int {
        let yearIndex = monthAndDayEndIndex + 1
        guard tokens.indices.contains(yearIndex),
              parseExplicitYear(normalized(tokens.word(at: yearIndex) ?? "")) != nil else {
            return monthAndDayEndIndex
        }

        return yearIndex
    }

    private static func parseExplicitYear(_ token: String) -> Int? {
        guard token.firstMatch(of: /^\d{4}$/) != nil,
              let year = Int(token),
              year > 0 else {
            return nil
        }

        return year
    }

    static func upcomingDate(
        month: Int,
        day: Int,
        calendar: Calendar,
        referenceDate: Date
    ) -> DateComponents? {
        let currentYear = calendar.component(.year, from: referenceDate)

        // A full Gregorian cycle guarantees a valid future occurrence for dates such as Feb 29.
        for year in currentYear...(currentYear + 400) {
            guard let components = dateComponents(
                year: year,
                month: month,
                day: day,
                calendar: calendar
            ), let date = calendar.date(from: components),
               date >= calendar.startOfDay(for: referenceDate) else {
                continue
            }

            return components
        }

        return nil
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

        return calendar.dateComponents(
            [.calendar, .timeZone, .year, .month, .day],
            from: date
        )
    }
}

struct QuickAddParseWords {
    enum Kind { case word, literal, suppressedMetadata, notes, eventTiming }
    struct Word {
        fileprivate let value: String?
        let range: NSRange
        let kind: Kind
        let eventTiming: QuickAddEventTimingToken?

        var containsNonPunctuation: Bool {
            value.map { !QuickAddParsingSupport.trimmingSentencePunctuation(from: $0).isEmpty } == true
        }
    }

    fileprivate let storage: [Word]
    var count: Int { storage.count }
    var indices: Range<Int> { storage.indices }
    subscript(index: Int) -> Word { storage[index] }

    func word(at index: Int) -> String? {
        indices.contains(index) && storage[index].kind == .word ? storage[index].value : nil
    }

    func normalized(at index: Int) -> String? {
        word(at: index).map(QuickAddParsingSupport.normalized)
    }

    func contiguousRange(from start: Int, through end: Int) -> NSRange? {
        guard indices.contains(start), indices.contains(end), start <= end,
              (start...end).allSatisfy({ storage[$0].kind == .word }) else { return nil }
        return QuickAddParsingSupport.union(storage[start].range, storage[end].range)
    }

    var beforeNotes: Self {
        Self(storage: Array(storage.prefix { $0.kind != .notes }))
    }
}

struct QuickAddEventTimingMatch {
    let timing: QuickAddEventTimingToken
    let startIndex: Int
    let endIndex: Int
}

struct QuickAddInput {
    private let source: String
    private let atoms: [QuickAddParseWords.Word]

    static func read(_ source: String, suppressedTokens: [QuickAddSuppressedToken]) -> Self {
        var inNotes = false
        let atoms = QuickAddParsingSupport.scanTokens(in: source).map { token in
            let suppression = suppressedTokens.first {
                NSIntersectionRange($0.range, token.range).length > 0 &&
                    NSMaxRange($0.range) <= (source as NSString).length &&
                    (source as NSString).substring(with: $0.range) == $0.text
            }
            if let suppression, !inNotes {
                let kind: QuickAddParseWords.Kind
                switch suppression.kind {
                case .list, .tag, .url, .priority:
                    kind = .suppressedMetadata
                default:
                    kind = .literal
                }
                return QuickAddParseWords.Word(value: token.text, range: token.range, kind: kind, eventTiming: nil)
            }
            inNotes = inNotes || token.text.hasPrefix("//")
            return QuickAddParseWords.Word(value: inNotes ? nil : token.text, range: token.range,
                                           kind: inNotes ? .notes : .word, eventTiming: nil)
        }
        return Self(source: source, atoms: atoms)
    }

    var parsingWords: QuickAddParseWords { QuickAddParseWords(storage: atoms) }

    func text(at index: Int) -> String {
        (source as NSString).substring(with: atoms[index].range)
    }

    func titleFragments(in indices: ClosedRange<Int>) -> [String] {
        indices.map { text(at: $0) }
    }

    func foldingEventTiming() -> Self {
        let words = parsingWords
        let matches = QuickAddEventTimingParser.matches(in: words)
        var folded: [QuickAddParseWords.Word] = []
        var index = 0
        for match in matches {
            folded.append(contentsOf: atoms[index..<match.startIndex])
            let range = words.contiguousRange(from: match.startIndex, through: match.endIndex)!
            folded.append(.init(value: nil, range: range, kind: .eventTiming, eventTiming: match.timing))
            index = match.endIndex + 1
        }
        folded.append(contentsOf: atoms[index...])
        return Self(source: source, atoms: folded)
    }
}
