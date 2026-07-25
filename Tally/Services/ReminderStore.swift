import EventKit
import AppKit
import Foundation

@MainActor
final class ReminderStore: ObservableObject {
    typealias AccessState = ReminderAccessState

    @Published private(set) var accessState: AccessState = .unknown
    @Published private(set) var reminders: [ReminderItem] = []
    @Published private(set) var reminderLists: [ReminderListInfo] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published var errorMessage: String?

    private let eventStore = EKEventStore()
    private let accessController: ReminderAccessController
    private var changeObserver: NSObjectProtocol?
    private var scheduledReloadTask: Task<Void, Never>?
    private var reloadGeneration = 0
    private let isUITesting: Bool

    var activeListTitle: String {
        if isUITesting {
            return reminderLists.first?.title ?? "Inbox"
        }

        guard accessState == .authorized else {
            return "Inbox"
        }

        return eventStore.defaultCalendarForNewReminders()?.title ?? "Inbox"
    }

    var reminderListTitles: [String] {
        reminderLists.map(\.title)
    }

    init() {
        #if DEBUG
        isUITesting = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        #else
        isUITesting = false
        #endif

        accessController = ReminderAccessController(eventStore: eventStore)

        if isUITesting {
            accessState = .authorized
            reminderLists = [
                ReminderListInfo(id: "ui-inbox", title: "Inbox"),
                ReminderListInfo(id: "ui-personal", title: "Personal"),
                ReminderListInfo(id: "ui-work", title: "Work")
            ]
            reminders = [
                ReminderItem(
                    id: "ui-review",
                    title: "Review launch checklist",
                    notes: nil,
                    listTitle: "Work",
                    dueDate: Calendar.current.dateComponents(
                        [.calendar, .timeZone, .year, .month, .day],
                        from: Date()
                    ),
                    priority: 1
                )
            ]
        }

        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: eventStore,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.scheduleReloadAfterExternalChange()
            }
        }
    }

    deinit {
        if let changeObserver {
            NotificationCenter.default.removeObserver(changeObserver)
        }
        scheduledReloadTask?.cancel()
    }

    func bootstrap() async {
        guard !isUITesting else {
            return
        }

        refreshAccessState()

        if accessState == .notDetermined {
            await requestAccess()
        }

        await reload()
    }

    func refreshAccessState() {
        guard !isUITesting else {
            accessState = .authorized
            return
        }

        accessState = accessController.currentState()
    }

    func requestAccess() async {
        guard !isUITesting else {
            accessState = .authorized
            return
        }

        let currentState = accessController.currentState()

        guard currentState == .notDetermined else {
            accessState = currentState
            return
        }

        accessState = .requesting
        accessState = await accessController.requestAccessIfNeeded()
    }

    @discardableResult
    func performAccessAction() async -> ReminderAccessAction {
        refreshAccessState()
        let action = accessState.availableAction

        switch action {
        case .request:
            await requestAccess()
            await reload()
        case .openSystemSettings:
            openRemindersPrivacySettings()
        case .none:
            break
        }

        return action
    }

    func reload() async {
        scheduledReloadTask?.cancel()
        scheduledReloadTask = nil
        await performReload()
    }

    private func performReload() async {
        guard !isUITesting else {
            return
        }

        refreshAccessState()

        guard accessState == .authorized else {
            reminders = []
            reminderLists = []
            isLoading = false
            return
        }

        reloadGeneration += 1
        let generation = reloadGeneration
        isLoading = true
        reminderLists = writableReminderLists()

        do {
            let fetchedReminders = try await fetchIncompleteReminders()
            guard generation == reloadGeneration else {
                return
            }

            reminders = fetchedReminders
                .map(ReminderItem.init(reminder:))
                .sorted(by: ReminderStore.sortReminders)
            errorMessage = nil
        } catch {
            if generation == reloadGeneration {
                errorMessage = error.localizedDescription
            }
        }

        if generation == reloadGeneration {
            isLoading = false
        }
    }

    @discardableResult
    func addReminder(_ request: ReminderCreationRequest) async -> Bool {
        guard !request.title.isEmpty else {
            return false
        }

        if isUITesting {
            return await addUITestingReminder(request)
        }

        guard await ensureAccessForUserAction() else {
            errorMessage = accessState.saveErrorMessage
            return false
        }

        isSaving = true
        defer { isSaving = false }

        do {
            guard let calendar = writableCalendar(for: request) else {
                throw ReminderStoreError.noWritableList
            }

            let reminder = EKReminder(eventStore: eventStore)
            reminder.title = request.title
            reminder.calendar = calendar
            reminder.priority = request.priority
            reminder.dueDateComponents = request.dueDate
            reminder.notes = request.combinedNotes

            try eventStore.save(reminder, commit: true)
            await reload()
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @available(*, deprecated, message: "Create a ReminderCreationRequest before saving.")
    func addReminder(
        from input: String,
        notes: String?,
        suppressedInferredTokens: [QuickAddSuppressedToken] = []
    ) async -> Bool {
        let fields = QuickAddParser.parse(input, suppressedInferredTokens: suppressedInferredTokens)
        guard !fields.title.isEmpty else {
            return false
        }

        return await addReminder(ReminderCreationRequest(
            title: fields.title,
            userNotes: notes,
            inlineNotes: fields.inlineNotes,
            tags: fields.tags,
            listIdentifier: nil,
            listName: fields.listName,
            dueDate: fields.dueDate,
            priority: fields.priority
        ))
    }

    func completeReminder(withID id: String) async {
        if isUITesting {
            reminders.removeAll { $0.id == id }
            return
        }

        guard await ensureAccessForUserAction() else {
            return
        }

        do {
            guard let reminder = eventStore.calendarItem(withIdentifier: id) as? EKReminder else {
                await reload()
                return
            }

            reminder.isCompleted = true
            try eventStore.save(reminder, commit: true)
            await reload()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteReminder(withID id: String) async {
        if isUITesting {
            reminders.removeAll { $0.id == id }
            return
        }

        guard await ensureAccessForUserAction() else {
            return
        }

        do {
            guard let reminder = eventStore.calendarItem(withIdentifier: id) as? EKReminder else {
                await reload()
                return
            }

            try eventStore.remove(reminder, commit: true)
            await reload()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openReminder(withID id: String) {
        guard eventStore.calendarItem(withIdentifier: id) is EKReminder else {
            return
        }

        // EventKit does not expose a public deep link for a specific Reminders item.
        openReminders()
    }

    func openReminders() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.reminders") else {
            return
        }

        NSWorkspace.shared.openApplication(
            at: url,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }

    private func openRemindersPrivacySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders"
        ) else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    private func fetchIncompleteReminders() async throws -> [EKReminder] {
        let predicate = eventStore.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: nil,
            calendars: nil
        )

        return await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }
    }

    func destinationListTitle(for request: ReminderCreationRequest) -> String {
        if isUITesting {
            return uiTestingList(for: request)?.title ?? activeListTitle
        }

        return writableCalendar(for: request)?.title ?? activeListTitle
    }

    func preferredList(for identifier: String?) -> ReminderListInfo? {
        guard let identifier else {
            return reminderLists.first { $0.title == activeListTitle }
        }

        return reminderLists.first { $0.id == identifier }
            ?? reminderLists.first { $0.title == activeListTitle }
    }

    private func writableCalendar(for request: ReminderCreationRequest) -> EKCalendar? {
        let calendars = eventStore
            .calendars(for: .reminder)
            .filter(\.allowsContentModifications)

        if let listIdentifier = request.listIdentifier,
           let calendar = calendars.first(where: { $0.calendarIdentifier == listIdentifier }) {
            return calendar
        }

        if let listName = request.listName,
           let matchingCalendar = eventStore
            .calendars(for: .reminder)
            .first(where: { calendar in
                calendar.allowsContentModifications &&
                    calendar.title.compare(
                        listName,
                        options: [.caseInsensitive, .diacriticInsensitive]
                    ) == .orderedSame
            }) {
            return matchingCalendar
        }

        if let defaultCalendar = eventStore.defaultCalendarForNewReminders(),
           defaultCalendar.allowsContentModifications {
            return defaultCalendar
        }

        return calendars.first
    }

    private func writableReminderLists() -> [ReminderListInfo] {
        eventStore
            .calendars(for: .reminder)
            .filter(\.allowsContentModifications)
            .map { ReminderListInfo(id: $0.calendarIdentifier, title: $0.title) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private func ensureAccessForUserAction() async -> Bool {
        let currentState = accessController.currentState()

        if currentState == .authorized {
            accessState = .authorized
            return true
        }

        if currentState == .notDetermined {
            await requestAccess()
            return accessState == .authorized
        }

        accessState = currentState
        return false
    }

    private func scheduleReloadAfterExternalChange() {
        guard !isUITesting else {
            return
        }

        scheduledReloadTask?.cancel()
        scheduledReloadTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else {
                return
            }

            await self?.performReload()
        }
    }

    private func addUITestingReminder(_ request: ReminderCreationRequest) async -> Bool {
        isSaving = true
        try? await Task.sleep(for: .milliseconds(120))
        let listTitle = uiTestingList(for: request)?.title ?? activeListTitle
        reminders.append(ReminderItem(
            id: "ui-\(UUID().uuidString)",
            title: request.title,
            notes: request.combinedNotes,
            listTitle: listTitle,
            dueDate: request.dueDate,
            priority: request.priority
        ))
        reminders.sort(by: ReminderStore.sortReminders)
        isSaving = false
        errorMessage = nil
        return true
    }

    private func uiTestingList(for request: ReminderCreationRequest) -> ReminderListInfo? {
        if let listIdentifier = request.listIdentifier,
           let list = reminderLists.first(where: { $0.id == listIdentifier }) {
            return list
        }

        if let listName = request.listName {
            return reminderLists.first {
                $0.title.compare(
                    listName,
                    options: [.caseInsensitive, .diacriticInsensitive]
                ) == .orderedSame
            }
        }

        return reminderLists.first
    }

    private static func sortReminders(_ lhs: ReminderItem, _ rhs: ReminderItem) -> Bool {
        switch (lhs.dueDate?.sortDate, rhs.dueDate?.sortDate) {
        case let (left?, right?) where left != right:
            return left < right
        case (nil, _?):
            return false
        case (_?, nil):
            return true
        default:
            break
        }

        let lhsPriority = lhs.priority == 0 ? Int.max : lhs.priority
        let rhsPriority = rhs.priority == 0 ? Int.max : rhs.priority

        if lhsPriority != rhsPriority {
            return lhsPriority < rhsPriority
        }

        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }
}

private extension DateComponents {
    var sortDate: Date? {
        Calendar.current.date(from: self)
    }
}

private enum ReminderStoreError: LocalizedError {
    case noWritableList

    var errorDescription: String? {
        switch self {
        case .noWritableList:
            return "No writable Reminders list is available."
        }
    }
}

private extension ReminderAccessState {
    var saveErrorMessage: String {
        switch self {
        case .notDetermined, .requesting:
            return "Waiting for Reminders access."
        case .denied:
            return "Reminders access is off. Enable it in System Settings."
        case .unknown:
            return "Tally could not verify Reminders access."
        case .authorized:
            return "The reminder could not be saved."
        }
    }
}
