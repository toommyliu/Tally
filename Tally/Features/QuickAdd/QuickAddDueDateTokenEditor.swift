import Foundation

struct QuickAddDueDateSelection: Equatable {
    var date: Date
    var includesTime: Bool
}

/// How long a Quick Add event should last, as picked from the duration menu.
enum QuickAddEventLength: Hashable {
    case duration(QuickAddEventDuration)
    case allDay
}

struct QuickAddTextEdit: Equatable {
    private(set) var text: String
    var selectedRange: NSRange? = nil
    private(set) var suppressedTokens: [QuickAddSuppressedToken] = []

    fileprivate mutating func replaceCharacters(in range: NSRange, with replacement: String) {
        guard let textRange = Range(range, in: text) else { return }
        let delta = replacement.utf16.count - range.length
        suppressedTokens = suppressedTokens.compactMap { suppression in
            var keptRange = suppression.range
            if NSMaxRange(range) <= keptRange.location {
                keptRange.location += delta
            } else if range.location < NSMaxRange(keptRange) {
                return nil
            }
            return QuickAddSuppressedToken(kind: suppression.kind, range: keptRange, text: suppression.text)
        }
        text.replaceSubrange(textRange, with: replacement)
        suppressedTokens = suppressedTokens.map { suppression in
            QuickAddSuppressedToken(kind: suppression.kind, range: suppression.range,
                text: (text as NSString).substring(with: suppression.range))
        }
    }

    fileprivate mutating func normalizeWhitespace() {
        let source = Array(text.utf16)
        let whitespace = CharacterSet.whitespacesAndNewlines
        func isWhitespace(_ unit: UInt16) -> Bool {
            UnicodeScalar(unit).map(whitespace.contains) == true
        }
        var index = 0
        while index < source.count {
            guard isWhitespace(source[index]) else { index += 1; continue }
            let start = index
            repeat { index += 1 } while index < source.count && isWhitespace(source[index])
            if source[start] != 32 || index - start != 1 || start == 0 || index == source.count {
                index = start
                break
            }
        }
        guard index < source.count else { return }
        var normalized = Array(source[..<index])
        normalized.reserveCapacity(source.count)
        var positions = Array(0...index)
        positions.reserveCapacity(source.count + 1)
        while index < source.count {
            if isWhitespace(source[index]) {
                let start = index
                repeat { index += 1 }
                while index < source.count && isWhitespace(source[index])
                if start > 0 && index < source.count { normalized.append(32) }
                positions.append(contentsOf: repeatElement(normalized.count, count: index - start))
            } else {
                normalized.append(source[index])
                positions.append(normalized.count)
                index += 1
            }
        }
        let normalizedText = String(decoding: normalized, as: UTF16.self)
        let result = normalizedText as NSString
        suppressedTokens = suppressedTokens.compactMap { suppression in
            var start = positions[suppression.range.location]
            var end = positions[NSMaxRange(suppression.range)]
            if start < end && normalized[start] == 32 { start += 1 }
            if start < end && normalized[end - 1] == 32 { end -= 1 }
            guard start < end else { return nil }
            let range = NSRange(location: start, length: end - start)
            return QuickAddSuppressedToken(kind: suppression.kind, range: range, text: result.substring(with: range))
        }
        text = normalizedText
    }
}

enum QuickAddTokenEditor {
    static func applyingDueDate(
        _ selection: QuickAddDueDateSelection?,
        to input: String,
        calendar: Calendar = .current,
        now: Date = Date(),
        suppressedTokens: [QuickAddSuppressedToken] = [],
        mode: QuickAddMode = .reminder
    ) -> QuickAddTextEdit {
        let fields = QuickAddParser.parse(
            input,
            mode: mode,
            calendar: calendar,
            now: now,
            suppressedTokens: suppressedTokens
        )
        guard let selection else {
            let tokensToRemove = fields.usedTokens.filter(\.isScheduleToken)

            return removingTokens(tokensToRemove, from: input, suppressedTokens: suppressedTokens)
        }

        var replacement = dueDateToken(for: selection, calendar: calendar)
        if selection.includesTime {
            if fields.usedTokens.contains(where: { $0.kind == .timeRange }),
               let minutes = fields.eventTiming?.durationMinutes {
                replacement += " \(QuickAddEventDuration.minutes(minutes).token)"
            }
        } else if let length = fields.eventDuration, length.unit == .days {
            replacement += " \(length.token)"
        }
        return replacingTokens(
            fields.usedTokens.filter { $0.isDueDateToken || (!selection.includesTime && $0.kind == .duration) },
            in: input,
            with: replacement,
            fields: fields,
            suppressedTokens: suppressedTokens
        )
    }

    static func applyingList(
        _ listTitle: String,
        to input: String,
        calendar: Calendar = .current,
        now: Date = Date(),
        suppressedTokens: [QuickAddSuppressedToken] = [],
        mode: QuickAddMode = .reminder
    ) -> QuickAddTextEdit {
        replacingTokens(
            in: input,
            matching: { $0.kind == .list },
            with: "#\(QuickAddListTokenCodec.encode(listTitle))",
            calendar: calendar,
            now: now,
            suppressedTokens: suppressedTokens,
            mode: mode
        )
    }

    static func clearingList(
        in input: String,
        calendar: Calendar = .current,
        now: Date = Date(),
        suppressedTokens: [QuickAddSuppressedToken] = [],
        mode: QuickAddMode = .reminder
    ) -> QuickAddTextEdit {
        replacingTokens(
            in: input,
            matching: { $0.kind == .list },
            with: nil,
            calendar: calendar,
            now: now,
            suppressedTokens: suppressedTokens,
            mode: mode
        )
    }

    static func applyingPriority(
        _ priority: Int,
        to input: String,
        calendar: Calendar = .current,
        now: Date = Date(),
        suppressedTokens: [QuickAddSuppressedToken] = [],
        mode: QuickAddMode = .reminder
    ) -> QuickAddTextEdit {
        replacingTokens(
            in: input,
            matching: { $0.kind == .priority },
            with: priorityToken(for: priority),
            calendar: calendar,
            now: now,
            suppressedTokens: suppressedTokens,
            mode: mode
        )
    }

    static func applyingEventLength(
        _ length: QuickAddEventLength,
        to input: String,
        calendar: Calendar = .current,
        now: Date = Date(),
        suppressedTokens: [QuickAddSuppressedToken] = []
    ) -> QuickAddTextEdit {
        let fields = QuickAddParser.parse(
            input,
            mode: .event,
            calendar: calendar,
            now: now,
            suppressedTokens: suppressedTokens
        )
        let lengthTokens = fields.usedTokens
            .filter { $0.kind == .timeRange || $0.kind == .duration }
            .sorted { $0.range.location < $1.range.location }

        switch length {
        case .allDay:
            guard let start = fields.eventTiming?.start,
                  let startDate = calendar.date(from: start) else {
                return removingTokens([], from: input, suppressedTokens: suppressedTokens)
            }

            var tokensToRemove = fields.usedTokens.filter {
                $0.isScheduleToken && $0.kind != .recurrence
            }
            if let range = fields.recurrenceTimeRange {
                tokensToRemove.append(QuickAddToken(kind: .time, range: range))
            }
            let replacement = fields.recurrence == nil ? dueDateToken(
                for: QuickAddDueDateSelection(date: startDate, includesTime: false),
                calendar: calendar
            ) : nil

            return replacingTokens(
                tokensToRemove,
                in: input,
                with: replacement,
                fields: fields,
                suppressedTokens: suppressedTokens
            )
        case let .duration(duration):
            var replacement = duration.token
            if lengthTokens.contains(where: { $0.kind == .timeRange }),
               let start = fields.eventTiming?.start,
               let hour = start.hour {
                replacement = "\(timeToken(hour: hour, minute: start.minute ?? 0)) \(replacement)"
            }

            return replacingTokens(lengthTokens, in: input, with: replacement, fields: fields, suppressedTokens: suppressedTokens)
        }
    }

    static func addingTagEntry(
        in input: String,
        calendar: Calendar = .current,
        now: Date = Date(),
        suppressedTokens: [QuickAddSuppressedToken] = [],
        mode: QuickAddMode = .reminder
    ) -> QuickAddTextEdit {
        let fields = QuickAddParser.parse(
            input,
            mode: mode,
            calendar: calendar,
            now: now,
            suppressedTokens: suppressedTokens
        )
        let pendingTagTokens = pendingTagTokens(in: fields, input: input)

        if let pendingEdit = reusingFirstPendingTag(pendingTagTokens, in: input, suppressedTokens: suppressedTokens) {
            return pendingEdit
        }

        var edit = appendingToken("@", to: input, fields: fields, suppressedTokens: suppressedTokens)
        edit.selectedRange = selectionAfterFirstPendingTag(in: edit.text)
        return edit
    }

    static func beginningTagEntry(
        in input: String,
        calendar: Calendar = .current,
        now: Date = Date(),
        suppressedTokens: [QuickAddSuppressedToken] = [],
        mode: QuickAddMode = .reminder
    ) -> QuickAddTextEdit {
        let fields = QuickAddParser.parse(
            input,
            mode: mode,
            calendar: calendar,
            now: now,
            suppressedTokens: suppressedTokens
        )
        let pendingTagTokens = pendingTagTokens(in: fields, input: input)
        let completedTagTokens = completedTagTokens(in: fields, input: input)

        if let pendingEdit = reusingFirstPendingTag(pendingTagTokens, in: input, suppressedTokens: suppressedTokens) {
            return pendingEdit
        }

        if let existingTag = completedTagTokens.last {
            return QuickAddTextEdit(
                text: input,
                selectedRange: selectionInsideTag(existingTag),
                suppressedTokens: suppressedTokens
            )
        }

        var edit = appendingToken("@", to: input, fields: fields, suppressedTokens: suppressedTokens)
        edit.selectedRange = selectionAfterFirstPendingTag(in: edit.text)
        return edit
    }

    static func editingTag(
        at index: Int,
        in input: String,
        calendar: Calendar = .current,
        now: Date = Date(),
        suppressedTokens: [QuickAddSuppressedToken] = [],
        mode: QuickAddMode = .reminder
    ) -> QuickAddTextEdit {
        let fields = QuickAddParser.parse(
            input,
            mode: mode,
            calendar: calendar,
            now: now,
            suppressedTokens: suppressedTokens
        )
        let completedTagTokens = completedTagTokens(in: fields, input: input)

        guard completedTagTokens.indices.contains(index) else {
            return beginningTagEntry(
                in: input,
                calendar: calendar,
                now: now,
                suppressedTokens: suppressedTokens,
                mode: mode
            )
        }

        return QuickAddTextEdit(
            text: input,
            selectedRange: selectionInsideTag(completedTagTokens[index]),
            suppressedTokens: suppressedTokens
        )
    }

    static func removingTag(
        at index: Int,
        from input: String,
        calendar: Calendar = .current,
        now: Date = Date(),
        suppressedTokens: [QuickAddSuppressedToken] = [],
        mode: QuickAddMode = .reminder
    ) -> QuickAddTextEdit {
        let fields = QuickAddParser.parse(
            input,
            mode: mode,
            calendar: calendar,
            now: now,
            suppressedTokens: suppressedTokens
        )
        let completedTagTokens = completedTagTokens(in: fields, input: input)

        guard completedTagTokens.indices.contains(index) else {
            return removingTokens([], from: input, suppressedTokens: suppressedTokens)
        }

        return removingTokens([completedTagTokens[index]], from: input, suppressedTokens: suppressedTokens)
    }

    static func dueDateToken(
        for selection: QuickAddDueDateSelection,
        calendar: Calendar = .current
    ) -> String {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: selection.date)
        let dateToken = String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 1,
            components.day ?? 1
        )

        guard selection.includesTime else {
            return dateToken
        }

        return "\(dateToken) \(timeToken(hour: components.hour ?? 0, minute: components.minute ?? 0))"
    }

    private static func replacingTokens(
        in input: String,
        matching predicate: (QuickAddToken) -> Bool,
        with replacement: String?,
        calendar: Calendar,
        now: Date,
        suppressedTokens: [QuickAddSuppressedToken],
        mode: QuickAddMode
    ) -> QuickAddTextEdit {
        let fields = QuickAddParser.parse(input, mode: mode, calendar: calendar, now: now,
            suppressedTokens: suppressedTokens)
        return replacingTokens(fields.usedTokens.filter(predicate), in: input, with: replacement,
            fields: fields, suppressedTokens: suppressedTokens)
    }

    private static func replacingTokens(
        _ tokens: [QuickAddToken],
        in input: String,
        with replacement: String?,
        fields: QuickAddFields,
        suppressedTokens: [QuickAddSuppressedToken]
    ) -> QuickAddTextEdit {
        guard let firstToken = tokens.min(by: { $0.range.location < $1.range.location }) else {
            guard let replacement else {
                return removingTokens([], from: input, suppressedTokens: suppressedTokens)
            }
            return appendingToken(replacement, to: input, fields: fields, suppressedTokens: suppressedTokens)
        }

        var edit = QuickAddTextEdit(text: input, suppressedTokens: suppressedTokens)
        for token in tokens.sorted(by: { $0.range.location > $1.range.location }) {
            edit.replaceCharacters(in: token.range, with: token == firstToken ? replacement ?? "" : "")
        }
        edit.normalizeWhitespace()
        return edit
    }

    private static func removingTokens(_ tokens: [QuickAddToken], from input: String,
                                       suppressedTokens: [QuickAddSuppressedToken]) -> QuickAddTextEdit {
        var edit = QuickAddTextEdit(text: input, suppressedTokens: suppressedTokens)
        for token in tokens.sorted(by: { $0.range.location > $1.range.location }) {
            edit.replaceCharacters(in: token.range, with: "")
        }
        edit.normalizeWhitespace()
        return edit
    }

    private static func appendingToken(
        _ token: String,
        to input: String,
        fields: QuickAddFields,
        suppressedTokens: [QuickAddSuppressedToken]
    ) -> QuickAddTextEdit {
        var edit = QuickAddTextEdit(text: input, suppressedTokens: suppressedTokens)
        if let noteToken = fields.usedTokens.first(where: { $0.kind == .note }) {
            edit.replaceCharacters(in: NSRange(location: noteToken.range.location, length: 0), with: "\(token) ")
        } else {
            edit.replaceCharacters(in: NSRange(location: input.utf16.count, length: 0), with: " \(token)")
        }
        edit.normalizeWhitespace()
        return edit
    }

    private static func priorityToken(for priority: Int) -> String? {
        switch priority {
        case 1:
            return "P1"
        case 5:
            return "P2"
        case 9:
            return "P3"
        default:
            return nil
        }
    }

    private static func tokenText(_ token: QuickAddToken, in input: String) -> String? {
        guard NSMaxRange(token.range) <= (input as NSString).length else {
            return nil
        }

        return (input as NSString).substring(with: token.range)
    }

    private static func pendingTagTokens(
        in fields: QuickAddFields,
        input: String
    ) -> [QuickAddToken] {
        fields.usedTokens
            .filter { $0.kind == .tag && tokenText($0, in: input) == "@" }
            .sorted { $0.range.location < $1.range.location }
    }

    private static func completedTagTokens(
        in fields: QuickAddFields,
        input: String
    ) -> [QuickAddToken] {
        fields.usedTokens
            .filter { token in
                guard token.kind == .tag,
                      let text = tokenText(token, in: input) else {
                    return false
                }

                return text != "@"
            }
            .sorted { $0.range.location < $1.range.location }
    }

    private static func reusingFirstPendingTag(
        _ pendingTagTokens: [QuickAddToken],
        in input: String,
        suppressedTokens: [QuickAddSuppressedToken]
    ) -> QuickAddTextEdit? {
        guard let firstPendingTag = pendingTagTokens.first else { return nil }
        var edit = removingTokens(Array(pendingTagTokens.dropFirst()), from: input, suppressedTokens: suppressedTokens)
        edit.selectedRange = selectionAfterPendingTag(
            matchingOriginalLocation: firstPendingTag.range.location,
            in: edit.text
        ) ?? selectionAfterFirstPendingTag(in: edit.text)
        return edit
    }

    private static func selectionAfterPendingTag(
        matchingOriginalLocation originalLocation: Int,
        in input: String
    ) -> NSRange? {
        let fields = QuickAddParser.parse(input)
        let matchingTag = fields.usedTokens.first { token in
            token.kind == .tag &&
                token.range.location == originalLocation &&
                tokenText(token, in: input) == "@"
        }

        guard let matchingTag else {
            return nil
        }

        return NSRange(location: NSMaxRange(matchingTag.range), length: 0)
    }

    private static func selectionAfterFirstPendingTag(in input: String) -> NSRange? {
        let fields = QuickAddParser.parse(input)
        let pendingTag = fields.usedTokens.first { token in
            token.kind == .tag && tokenText(token, in: input) == "@"
        }

        guard let pendingTag else {
            return nil
        }

        return NSRange(location: NSMaxRange(pendingTag.range), length: 0)
    }

    private static func selectionInsideTag(_ token: QuickAddToken) -> NSRange {
        NSRange(location: token.range.location + 1, length: max(token.range.length - 1, 0))
    }

    private static func timeToken(hour: Int, minute: Int) -> String {
        let suffix = hour >= 12 ? "pm" : "am"
        let displayHour = {
            let value = hour % 12
            return value == 0 ? 12 : value
        }()

        return String(format: "%d:%02d%@", displayHour, minute, suffix)
    }
}

private extension QuickAddToken {
    var isDueDateToken: Bool {
        kind == .date || kind == .time || kind == .timeRange || kind == .recurrence
    }

    var isScheduleToken: Bool {
        isDueDateToken || kind == .duration
    }
}

enum QuickAddDueDateTokenEditor {
    static func applying(
        _ selection: QuickAddDueDateSelection?,
        to input: String,
        calendar: Calendar = .current,
        now: Date = Date(),
        suppressedTokens: [QuickAddSuppressedToken] = []
    ) -> QuickAddTextEdit {
        QuickAddTokenEditor.applyingDueDate(
            selection,
            to: input,
            calendar: calendar,
            now: now,
            suppressedTokens: suppressedTokens
        )
    }

    static func token(
        for selection: QuickAddDueDateSelection,
        calendar: Calendar = .current
    ) -> String {
        QuickAddTokenEditor.dueDateToken(for: selection, calendar: calendar)
    }
}
