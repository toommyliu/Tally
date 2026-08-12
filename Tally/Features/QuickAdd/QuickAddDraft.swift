import Foundation

@MainActor
final class QuickAddDraft: ObservableObject {
    @Published private(set) var suppressedTokens: [QuickAddSuppressedToken] = []

    @Published var text = "" {
        didSet {
            suppressedTokens = Self.reconciledSuppressions(
                suppressedTokens,
                from: oldValue,
                to: text
            )
            clearTransientFeedback()
            reconcileSelectedList()
        }
    }

    @Published var notes = "" {
        didSet {
            clearTransientFeedback()
        }
    }

    @Published var keepsOpenAfterAdd: Bool
    @Published var selectedRangeRequest: NSRange?
    @Published var notesFocusRequestID = 0
    @Published private(set) var errorMessage: String?
    @Published private(set) var confirmationMessage: String?

    private var selectedList: ReminderListInfo?
    private let settingsStore: AppSettingsStore

    init(settingsStore: AppSettingsStore) {
        self.settingsStore = settingsStore
        keepsOpenAfterAdd = settingsStore.quickAddBehavior == .keepOpen
    }

    var fields: QuickAddFields {
        QuickAddParser.parse(text, suppressedTokens: suppressedTokens)
    }

    var canSubmit: Bool {
        !fields.title.isEmpty
    }

    var defaultListIdentifier: String? {
        settingsStore.defaultListIdentifier
    }

    func makeRequest() -> ReminderCreationRequest? {
        let fields = fields
        guard !fields.title.isEmpty else {
            return nil
        }

        let selectedIdentifier: String?
        if let listName = fields.listName,
           let selectedList,
           selectedList.title.compare(
            listName,
            options: [.caseInsensitive, .diacriticInsensitive]
           ) == .orderedSame {
            selectedIdentifier = selectedList.id
        } else if fields.listName == nil {
            selectedIdentifier = settingsStore.defaultListIdentifier
        } else {
            selectedIdentifier = nil
        }

        return ReminderCreationRequest(
            title: fields.title,
            userNotes: notes,
            inlineNotes: fields.inlineNotes,
            tags: fields.tags,
            listIdentifier: selectedIdentifier,
            listName: fields.listName,
            dueDate: fields.dueDate,
            recurrence: fields.recurrence,
            earlyReminder: fields.earlyReminder,
            url: fields.url,
            priority: fields.priority
        )
    }

    func applyDueDate(_ selection: QuickAddDueDateSelection?) {
        let updatedText = QuickAddTokenEditor.applyingDueDate(
            selection,
            to: text,
            suppressedTokens: suppressedTokens
        )
        applyProgrammaticTextEdit(updatedText)
    }

    func selectList(_ list: ReminderListInfo) {
        selectedList = list
        let updatedText = QuickAddTokenEditor.applyingList(
            list.title,
            to: text,
            suppressedTokens: suppressedTokens
        )
        applyProgrammaticTextEdit(updatedText)
    }

    func useDefaultList() {
        selectedList = nil
        let updatedText = QuickAddTokenEditor.clearingList(
            in: text,
            suppressedTokens: suppressedTokens
        )
        applyProgrammaticTextEdit(updatedText)
    }

    func applyPriority(_ priority: Int) {
        let updatedText = QuickAddTokenEditor.applyingPriority(
            priority,
            to: text,
            suppressedTokens: suppressedTokens
        )
        applyProgrammaticTextEdit(updatedText)
    }

    func addTagEntry() {
        let edit = QuickAddTokenEditor.addingTagEntry(
            in: text,
            suppressedTokens: suppressedTokens
        )
        applyProgrammaticTextEdit(edit.text)
        selectedRangeRequest = edit.selectedRange
    }

    func editTag(at index: Int) {
        let edit = QuickAddTokenEditor.editingTag(
            at: index,
            in: text,
            suppressedTokens: suppressedTokens
        )
        applyProgrammaticTextEdit(edit.text)
        selectedRangeRequest = edit.selectedRange
    }

    func removeTag(at index: Int) {
        let updatedText = QuickAddTokenEditor.removingTag(
            at: index,
            from: text,
            suppressedTokens: suppressedTokens
        )
        applyProgrammaticTextEdit(updatedText)
    }

    /// Keeps the highlighted token at the current selection as literal title text.
    func keepTokenAsText(at selectedRange: NSRange) -> Bool {
        guard selectedRange.location != NSNotFound,
              let token = fields.usedTokens.first(where: {
                  Self.token($0, intersects: selectedRange)
              }),
              NSMaxRange(token.range) <= (text as NSString).length else {
            return false
        }

        suppressedTokens.append(QuickAddSuppressedToken(
            kind: token.kind,
            range: token.range,
            text: (text as NSString).substring(with: token.range)
        ))
        return true
    }

    func focusNotes() {
        notesFocusRequestID += 1
    }

    func focusTitleAtEnd() {
        selectedRangeRequest = NSRange(location: (text as NSString).length, length: 0)
    }

    func reportSaveFailure(_ message: String) {
        confirmationMessage = nil
        errorMessage = message
    }

    func didSave(to listTitle: String) {
        text = ""
        notes = ""
        suppressedTokens = []
        selectedList = nil
        selectedRangeRequest = NSRange(location: 0, length: 0)
        errorMessage = nil
        confirmationMessage = "Added to \(listTitle)"
    }

    private func reconcileSelectedList() {
        guard let selectedList else {
            return
        }

        guard let parsedListName = fields.listName,
              selectedList.title.compare(
                parsedListName,
                options: [.caseInsensitive, .diacriticInsensitive]
              ) == .orderedSame
        else {
            self.selectedList = nil
            return
        }
    }

    private func clearTransientFeedback() {
        errorMessage = nil
        confirmationMessage = nil
    }

    /// Keeps unchanged literal opt-outs attached across token-editor rewrites.
    private func applyProgrammaticTextEdit(_ updatedText: String) {
        let preservedSuppressions = Self.reanchoredSuppressions(
            suppressedTokens,
            from: text,
            to: updatedText
        )
        text = updatedText
        suppressedTokens = preservedSuppressions
    }

    private static func token(_ token: QuickAddToken, intersects selectedRange: NSRange) -> Bool {
        if selectedRange.length > 0 {
            return NSIntersectionRange(token.range, selectedRange).length > 0
        }

        return NSLocationInRange(selectedRange.location, token.range) ||
            selectedRange.location == NSMaxRange(token.range)
    }

    private static func reconciledSuppressions(
        _ suppressions: [QuickAddSuppressedToken],
        from oldText: String,
        to newText: String
    ) -> [QuickAddSuppressedToken] {
        guard oldText != newText, !suppressions.isEmpty else {
            return suppressions
        }

        let edit = changedTextRange(from: oldText, to: newText)
        let offset = edit.replacementLength - edit.oldRange.length
        let newText = newText as NSString

        return suppressions.compactMap { suppression in
            var range = suppression.range
            let replacementRange = NSRange(
                location: edit.oldRange.location,
                length: edit.replacementLength
            )
            let replacement = newText.substring(with: replacementRange)
            if edit.oldRange.location >= NSMaxRange(range) {
                if editExtendsSuppressedToken(
                    edit,
                    replacement: replacement,
                    oldText: oldText,
                    suppression: suppression
                ) {
                    return nil
                }

                // The edit follows this suppression, so its range is unchanged.
            } else if NSMaxRange(edit.oldRange) <= range.location {
                range.location += offset
            } else {
                return nil
            }

            guard range.location >= 0,
                  NSMaxRange(range) <= newText.length,
                  newText.substring(with: range) == suppression.text else {
                return nil
            }

            return QuickAddSuppressedToken(
                kind: suppression.kind,
                range: range,
                text: suppression.text
            )
        }
    }

    /// Reanchors unchanged literal opt-outs after a programmatic edit performs several removals.
    private static func reanchoredSuppressions(
        _ suppressions: [QuickAddSuppressedToken],
        from oldText: String,
        to newText: String
    ) -> [QuickAddSuppressedToken] {
        guard oldText != newText else {
            return suppressions
        }

        return suppressions.compactMap { suppression in
            let candidates = ranges(of: suppression.text, in: newText)
            guard !candidates.isEmpty else {
                return nil
            }

            guard let range = candidates.max(by: { lhs, rhs in
                suppressionContextScore(
                    candidate: lhs,
                    suppression: suppression,
                    oldText: oldText,
                    newText: newText
                ) < suppressionContextScore(
                    candidate: rhs,
                    suppression: suppression,
                    oldText: oldText,
                    newText: newText
                )
            }) else {
                return nil
            }

            return QuickAddSuppressedToken(
                kind: suppression.kind,
                range: range,
                text: suppression.text
            )
        }
    }

    private static func suppressionContextScore(
        candidate: NSRange,
        suppression: QuickAddSuppressedToken,
        oldText: String,
        newText: String
    ) -> Int {
        let old = oldText as NSString
        let new = newText as NSString
        let oldPrefix = old.substring(to: suppression.range.location)
        let newPrefix = new.substring(to: candidate.location)
        let oldSuffix = old.substring(from: NSMaxRange(suppression.range))
        let newSuffix = new.substring(from: NSMaxRange(candidate))

        var score = commonSuffixLength(oldPrefix, newPrefix) +
            commonPrefixLength(oldSuffix, newSuffix)

        if oldPrefix.isEmpty && newPrefix.isEmpty {
            score += 10_000
        }
        if oldSuffix.isEmpty && newSuffix.isEmpty {
            score += 10_000
        }

        return score
    }

    private static func commonPrefixLength(_ lhs: String, _ rhs: String) -> Int {
        let lhsUnits = Array(lhs.utf16)
        let rhsUnits = Array(rhs.utf16)
        return zip(lhsUnits, rhsUnits).prefix { pair in pair.0 == pair.1 }.count
    }

    private static func commonSuffixLength(_ lhs: String, _ rhs: String) -> Int {
        commonPrefixLength(String(lhs.reversed()), String(rhs.reversed()))
    }

    private static func ranges(of text: String, in input: String) -> [NSRange] {
        guard !text.isEmpty else {
            return []
        }

        let searchableText = input as NSString
        var searchRange = NSRange(location: 0, length: searchableText.length)
        var matches: [NSRange] = []

        while searchRange.length > 0 {
            let match = searchableText.range(of: text, options: [], range: searchRange)
            guard match.location != NSNotFound else {
                break
            }

            matches.append(match)
            let nextLocation = NSMaxRange(match)
            searchRange = NSRange(
                location: nextLocation,
                length: searchableText.length - nextLocation
            )
        }

        return matches
    }

    private static func editExtendsSuppressedToken(
        _ edit: (oldRange: NSRange, replacementLength: Int),
        replacement: String,
        oldText: String,
        suppression: QuickAddSuppressedToken
    ) -> Bool {
        let suppressionEnd = NSMaxRange(suppression.range)
        guard edit.oldRange.location >= suppressionEnd else {
            return false
        }

        let gapRange = NSRange(
            location: suppressionEnd,
            length: edit.oldRange.location - suppressionEnd
        )
        let gap = (oldText as NSString).substring(with: gapRange)
        guard !gap.contains(where: { $0.isWhitespace }) else {
            return false
        }

        let extensionText = gap + replacement
        guard !extensionText.isEmpty,
              !extensionText.contains(where: { $0.isWhitespace }) else {
            return false
        }

        return !isExternalURLPunctuation(extensionText, for: suppression)
    }

    /// Sentence punctuation is outside a URL token, so adding it does not opt NLP back in.
    private static func isExternalURLPunctuation(
        _ replacement: String,
        for suppression: QuickAddSuppressedToken
    ) -> Bool {
        suppression.kind == .url &&
            !replacement.isEmpty &&
            QuickAddReminderMetadataParser.isExternalURLPunctuation(replacement)
    }

    private static func changedTextRange(
        from oldText: String,
        to newText: String
    ) -> (oldRange: NSRange, replacementLength: Int) {
        let oldUnits = Array(oldText.utf16)
        let newUnits = Array(newText.utf16)
        let sharedLimit = min(oldUnits.count, newUnits.count)
        var prefixLength = 0

        while prefixLength < sharedLimit,
              oldUnits[prefixLength] == newUnits[prefixLength] {
            prefixLength += 1
        }

        let suffixLimit = sharedLimit - prefixLength
        var suffixLength = 0

        while suffixLength < suffixLimit,
              oldUnits[oldUnits.count - suffixLength - 1] ==
              newUnits[newUnits.count - suffixLength - 1] {
            suffixLength += 1
        }

        return (
            NSRange(
                location: prefixLength,
                length: oldUnits.count - prefixLength - suffixLength
            ),
            newUnits.count - prefixLength - suffixLength
        )
    }
}
