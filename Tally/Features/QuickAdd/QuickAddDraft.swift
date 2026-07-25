import Foundation

@MainActor
final class QuickAddDraft: ObservableObject {
    @Published var text = "" {
        didSet {
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
        QuickAddParser.parse(text)
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
            priority: fields.priority
        )
    }

    func applyDueDate(_ selection: QuickAddDueDateSelection?) {
        text = QuickAddTokenEditor.applyingDueDate(selection, to: text)
    }

    func selectList(_ list: ReminderListInfo) {
        selectedList = list
        text = QuickAddTokenEditor.applyingList(list.title, to: text)
    }

    func useDefaultList() {
        selectedList = nil
        text = QuickAddTokenEditor.clearingList(in: text)
    }

    func applyPriority(_ priority: Int) {
        text = QuickAddTokenEditor.applyingPriority(priority, to: text)
    }

    func addTagEntry() {
        let edit = QuickAddTokenEditor.addingTagEntry(in: text)
        text = edit.text
        selectedRangeRequest = edit.selectedRange
    }

    func editTag(at index: Int) {
        let edit = QuickAddTokenEditor.editingTag(at: index, in: text)
        text = edit.text
        selectedRangeRequest = edit.selectedRange
    }

    func removeTag(at index: Int) {
        text = QuickAddTokenEditor.removingTag(at: index, from: text)
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
}
