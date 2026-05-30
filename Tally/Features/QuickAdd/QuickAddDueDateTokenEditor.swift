import Foundation

struct QuickAddDueDateSelection: Equatable {
    var date: Date
    var includesTime: Bool
}

struct QuickAddTextEdit: Equatable {
    var text: String
    var selectedRange: NSRange?
}

enum QuickAddTokenEditor {
    static func applyingDueDate(
        _ selection: QuickAddDueDateSelection?,
        to input: String,
        calendar: Calendar = .current,
        now: Date = Date(),
        suppressedInferredTokens: [QuickAddSuppressedToken] = []
    ) -> String {
        let fields = QuickAddParser.parse(
            input,
            calendar: calendar,
            now: now,
            suppressedInferredTokens: suppressedInferredTokens
        )
        let existingToken = fields.usedTokens.first { token in
            token.kind == .date || token.kind == .time
        }

        guard let selection else {
            guard let existingToken,
                  let range = Range(existingToken.range, in: input) else {
                return normalized(input)
            }

            var updated = input
            updated.removeSubrange(range)
            return normalized(updated)
        }

        let replacement = dueDateToken(for: selection, calendar: calendar)

        guard let existingToken,
              let range = Range(existingToken.range, in: input) else {
            return appendingToken(replacement, to: input)
        }

        var updated = input
        updated.replaceSubrange(range, with: replacement)
        return normalized(updated)
    }

    static func applyingList(
        _ listTitle: String,
        to input: String,
        calendar: Calendar = .current,
        now: Date = Date(),
        suppressedInferredTokens: [QuickAddSuppressedToken] = []
    ) -> String {
        replacingTokens(
            in: input,
            matching: { $0.kind == .list },
            with: "#\(QuickAddListTokenCodec.encode(listTitle))",
            calendar: calendar,
            now: now,
            suppressedInferredTokens: suppressedInferredTokens
        )
    }

    static func applyingPriority(
        _ priority: Int,
        to input: String,
        calendar: Calendar = .current,
        now: Date = Date(),
        suppressedInferredTokens: [QuickAddSuppressedToken] = []
    ) -> String {
        replacingTokens(
            in: input,
            matching: { $0.kind == .priority },
            with: priorityToken(for: priority),
            calendar: calendar,
            now: now,
            suppressedInferredTokens: suppressedInferredTokens
        )
    }

    static func addingTagEntry(
        in input: String,
        calendar: Calendar = .current,
        now: Date = Date(),
        suppressedInferredTokens: [QuickAddSuppressedToken] = []
    ) -> QuickAddTextEdit {
        let fields = QuickAddParser.parse(
            input,
            calendar: calendar,
            now: now,
            suppressedInferredTokens: suppressedInferredTokens
        )
        let pendingTagTokens = pendingTagTokens(in: fields, input: input)

        if let pendingEdit = reusingFirstPendingTag(pendingTagTokens, in: input) {
            return pendingEdit
        }

        let updated = appendingToken("@", to: input)
        return QuickAddTextEdit(
            text: updated,
            selectedRange: NSRange(location: (updated as NSString).length, length: 0)
        )
    }

    static func beginningTagEntry(
        in input: String,
        calendar: Calendar = .current,
        now: Date = Date(),
        suppressedInferredTokens: [QuickAddSuppressedToken] = []
    ) -> QuickAddTextEdit {
        let fields = QuickAddParser.parse(
            input,
            calendar: calendar,
            now: now,
            suppressedInferredTokens: suppressedInferredTokens
        )
        let pendingTagTokens = pendingTagTokens(in: fields, input: input)
        let completedTagTokens = completedTagTokens(in: fields, input: input)

        if let pendingEdit = reusingFirstPendingTag(pendingTagTokens, in: input) {
            return pendingEdit
        }

        if let existingTag = completedTagTokens.last {
            return QuickAddTextEdit(
                text: input,
                selectedRange: selectionInsideTag(existingTag)
            )
        }

        let updated = appendingToken("@", to: input)
        return QuickAddTextEdit(
            text: updated,
            selectedRange: NSRange(location: (updated as NSString).length, length: 0)
        )
    }

    static func editingTag(
        at index: Int,
        in input: String,
        calendar: Calendar = .current,
        now: Date = Date(),
        suppressedInferredTokens: [QuickAddSuppressedToken] = []
    ) -> QuickAddTextEdit {
        let fields = QuickAddParser.parse(
            input,
            calendar: calendar,
            now: now,
            suppressedInferredTokens: suppressedInferredTokens
        )
        let completedTagTokens = completedTagTokens(in: fields, input: input)

        guard completedTagTokens.indices.contains(index) else {
            return beginningTagEntry(
                in: input,
                calendar: calendar,
                now: now,
                suppressedInferredTokens: suppressedInferredTokens
            )
        }

        return QuickAddTextEdit(
            text: input,
            selectedRange: selectionInsideTag(completedTagTokens[index])
        )
    }

    static func removingTag(
        at index: Int,
        from input: String,
        calendar: Calendar = .current,
        now: Date = Date(),
        suppressedInferredTokens: [QuickAddSuppressedToken] = []
    ) -> String {
        let fields = QuickAddParser.parse(
            input,
            calendar: calendar,
            now: now,
            suppressedInferredTokens: suppressedInferredTokens
        )
        let completedTagTokens = completedTagTokens(in: fields, input: input)

        guard completedTagTokens.indices.contains(index) else {
            return normalized(input)
        }

        return normalized(removingTokens([completedTagTokens[index]], from: input))
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
        suppressedInferredTokens: [QuickAddSuppressedToken]
    ) -> String {
        let fields = QuickAddParser.parse(
            input,
            calendar: calendar,
            now: now,
            suppressedInferredTokens: suppressedInferredTokens
        )
        let matchingTokens = fields.usedTokens
            .filter(predicate)
            .sorted { $0.range.location < $1.range.location }

        guard let firstToken = matchingTokens.first else {
            guard let replacement else {
                return normalized(input)
            }

            return appendingToken(replacement, to: input)
        }

        var updated = removingTokens(matchingTokens, from: input)

        if let replacement,
           let insertionIndex = stringIndex(atUTF16Offset: firstToken.range.location, in: updated) {
            updated.insert(contentsOf: replacement, at: insertionIndex)
        }

        return normalized(updated)
    }

    private static func removingTokens(_ tokens: [QuickAddToken], from input: String) -> String {
        var updated = input
        let sortedTokens = tokens.sorted { $0.range.location > $1.range.location }

        for token in sortedTokens {
            guard let range = Range(token.range, in: updated) else {
                continue
            }

            updated.removeSubrange(range)
        }

        return updated
    }

    private static func appendingToken(_ token: String, to input: String) -> String {
        let cleanedInput = normalized(input)
        guard !cleanedInput.isEmpty else {
            return token
        }

        return "\(cleanedInput) \(token)"
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
        in input: String
    ) -> QuickAddTextEdit? {
        guard let firstPendingTag = pendingTagTokens.first else {
            return nil
        }

        let updated = normalized(removingTokens(Array(pendingTagTokens.dropFirst()), from: input))
        return QuickAddTextEdit(
            text: updated,
            selectedRange: selectionAfterPendingTag(
                matchingOriginalLocation: firstPendingTag.range.location,
                in: updated
            ) ?? selectionAfterFirstPendingTag(in: updated)
        )
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

    private static func stringIndex(atUTF16Offset offset: Int, in string: String) -> String.Index? {
        guard offset <= string.utf16.count,
              let utf16Index = string.utf16.index(
                string.utf16.startIndex,
                offsetBy: offset,
                limitedBy: string.utf16.endIndex
              ) else {
            return nil
        }

        return String.Index(utf16Index, within: string)
    }

    private static func timeToken(hour: Int, minute: Int) -> String {
        let suffix = hour >= 12 ? "pm" : "am"
        let displayHour = {
            let value = hour % 12
            return value == 0 ? 12 : value
        }()

        return String(format: "%d:%02d%@", displayHour, minute, suffix)
    }

    private static func normalized(_ input: String) -> String {
        input
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

enum QuickAddDueDateTokenEditor {
    static func applying(
        _ selection: QuickAddDueDateSelection?,
        to input: String,
        calendar: Calendar = .current,
        now: Date = Date(),
        suppressedInferredTokens: [QuickAddSuppressedToken] = []
    ) -> String {
        QuickAddTokenEditor.applyingDueDate(
            selection,
            to: input,
            calendar: calendar,
            now: now,
            suppressedInferredTokens: suppressedInferredTokens
        )
    }

    static func token(
        for selection: QuickAddDueDateSelection,
        calendar: Calendar = .current
    ) -> String {
        QuickAddTokenEditor.dueDateToken(for: selection, calendar: calendar)
    }
}
