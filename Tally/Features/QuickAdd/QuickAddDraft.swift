import Foundation

enum QuickAddSubmission: Equatable {
    case reminder(ReminderCreationRequest)
    case event(CalendarEventCreationRequest)
}

@MainActor
final class QuickAddDraft: ObservableObject {
    /// Switching keeps the typed text and reads it again for the new mode.
    @Published var mode: QuickAddMode = .reminder {
        didSet {
            guard mode != oldValue else {
                return
            }

            // A picked reminder list isn't a calendar, so only the typed name carries over.
            selectedList = nil
            clearTransientFeedback()
        }
    }

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
    @Published var isPinned = false
    @Published var selectedRangeRequest: NSRange?
    @Published var notesFocusRequestID = 0
    @Published private(set) var errorMessage: String?
    @Published private(set) var confirmationMessage: String?
    @Published private(set) var isSaving = false

    private var selectedList: CalendarDestinationInfo?
    private let settingsStore: AppSettingsStore

    private let calendar: Calendar
    private let now: () -> Date

    init(settingsStore: AppSettingsStore, calendar: Calendar = .current, now: @escaping () -> Date = Date.init) {
        self.calendar = calendar
        self.now = now
        self.settingsStore = settingsStore
        keepsOpenAfterAdd = settingsStore.quickAddBehavior == .keepOpen
    }

    func captureContext() -> QuickAddParseContext { QuickAddParseContext(calendar: calendar, now: now()) }

    func fields(in context: QuickAddParseContext) -> QuickAddFields {
        QuickAddParser.parse(text, mode: mode, calendar: context.calendar, now: context.now, suppressedTokens: suppressedTokens)
    }

    var fields: QuickAddFields { fields(in: captureContext()) }
    var canSubmit: Bool { canSubmit(fields) }

    func canSubmit(_ fields: QuickAddFields) -> Bool {
        !isSaving && !fields.title.isEmpty && (mode == .reminder || fields.eventTiming != nil)
    }

    /// The configured default reminder list. Events always use the system default calendar.
    var defaultListIdentifier: String? {
        mode == .reminder ? settingsStore.defaultListIdentifier : nil
    }

    func makeSubmission() -> QuickAddSubmission? {
        switch mode {
        case .reminder:
            return makeReminderRequest().map(QuickAddSubmission.reminder)
        case .event:
            return makeEventRequest().map(QuickAddSubmission.event)
        }
    }

    func makeReminderRequest() -> ReminderCreationRequest? {
        let fields = QuickAddParser.parse(text, mode: .reminder, calendar: calendar, now: now(), suppressedTokens: suppressedTokens)
        guard !fields.title.isEmpty else {
            return nil
        }

        return ReminderCreationRequest(
            title: fields.title,
            userNotes: notes,
            inlineNotes: fields.inlineNotes,
            tags: fields.tags,
            listIdentifier: selectedDestinationIdentifier(for: fields),
            listName: fields.listName,
            dueDate: fields.dueDate,
            recurrence: fields.recurrence,
            earlyReminder: fields.earlyReminder?.reminderValue,
            url: fields.url,
            priority: fields.priority
        )
    }

    func makeEventRequest() -> CalendarEventCreationRequest? {
        let fields = QuickAddParser.parse(text, mode: .event, calendar: calendar, now: now(), suppressedTokens: suppressedTokens)
        guard !fields.title.isEmpty, let timing = fields.eventTiming else {
            return nil
        }

        return CalendarEventCreationRequest(
            title: fields.title,
            userNotes: notes,
            inlineNotes: fields.inlineNotes,
            tags: fields.tags,
            calendarIdentifier: selectedDestinationIdentifier(for: fields),
            calendarName: fields.listName,
            timing: timing,
            recurrence: fields.recurrence,
            alert: fields.earlyReminder?.eventValue,
            url: fields.url
        )
    }

    func applyEarlyReminder(_ offset: ReminderEarlyReminder?) {
        let context = captureContext()
        applyProgrammaticTextEdit(QuickAddTokenEditor.applyingEarlyReminder(
            offset, to: text, calendar: context.calendar, now: context.now,
            suppressedTokens: suppressedTokens, mode: mode))
    }

    func applyDueDate(_ selection: QuickAddDueDateSelection?) {
        let updatedText = QuickAddTokenEditor.applyingDueDate(
            selection,
            to: text,
            calendar: calendar,
            now: now(),
            suppressedTokens: suppressedTokens,
            mode: mode
        )
        applyProgrammaticTextEdit(updatedText)
    }

    func applyEventLength(_ length: QuickAddEventLength) {
        let updatedText = QuickAddTokenEditor.applyingEventLength(
            length,
            to: text,
            calendar: calendar,
            now: now(),
            suppressedTokens: suppressedTokens
        )
        applyProgrammaticTextEdit(updatedText)
    }

    func selectList(_ list: CalendarDestinationInfo) {
        selectedList = list
        let updatedText = QuickAddTokenEditor.applyingList(
            list.title,
            to: text,
            calendar: calendar,
            now: now(),
            suppressedTokens: suppressedTokens,
            mode: mode
        )
        applyProgrammaticTextEdit(updatedText)
    }

    func useDefaultList() {
        selectedList = nil
        let updatedText = QuickAddTokenEditor.clearingList(
            in: text,
            suppressedTokens: suppressedTokens,
            mode: mode
        )
        applyProgrammaticTextEdit(updatedText)
    }

    func applyPriority(_ priority: Int) {
        let updatedText = QuickAddTokenEditor.applyingPriority(
            priority,
            to: text,
            calendar: calendar,
            now: now(),
            suppressedTokens: suppressedTokens,
            mode: mode
        )
        applyProgrammaticTextEdit(updatedText)
    }

    func addTagEntry() {
        let edit = QuickAddTokenEditor.addingTagEntry(
            in: text,
            suppressedTokens: suppressedTokens,
            mode: mode
        )
        applyProgrammaticTextEdit(edit)
        selectedRangeRequest = edit.selectedRange
    }

    func editTag(at index: Int) {
        let edit = QuickAddTokenEditor.editingTag(
            at: index,
            in: text,
            suppressedTokens: suppressedTokens,
            mode: mode
        )
        applyProgrammaticTextEdit(edit)
        selectedRangeRequest = edit.selectedRange
    }

    func removeTag(at index: Int) {
        let updatedText = QuickAddTokenEditor.removingTag(
            at: index,
            from: text,
            suppressedTokens: suppressedTokens,
            mode: mode
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

    func willSave() {
        isSaving = true
    }

    func reportSaveFailure(_ message: String) {
        isSaving = false
        confirmationMessage = nil
        errorMessage = message
    }

    /// A list or calendar picked from the menu wins over a same-named one, so
    /// duplicate names across accounts still save where the user chose.
    private func selectedDestinationIdentifier(for fields: QuickAddFields) -> String? {
        if let listName = fields.listName,
           let selectedList,
           selectedList.title.compare(
            listName,
            options: [.caseInsensitive, .diacriticInsensitive]
           ) == .orderedSame {
            return selectedList.id
        }

        return fields.listName == nil ? defaultListIdentifier : nil
    }

    func didSave(to listTitle: String) {
        isSaving = false
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

    private func applyProgrammaticTextEdit(_ edit: QuickAddTextEdit) {
        text = edit.text
        suppressedTokens = edit.suppressedTokens
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
