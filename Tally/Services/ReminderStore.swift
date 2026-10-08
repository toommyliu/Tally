import Combine
import EventKit
import Foundation

@MainActor
final class ReminderStore: ObservableObject {
    @Published private(set) var reminders: [ReminderItem] = []
    @Published private(set) var reminderLists: [ReminderListInfo] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published var errorMessage: String?

    let access: EventKitAccessController

    private let eventKit: EventKitService
    private var changeSubscription: AnyCancellable?
    private var scheduledReloadTask: Task<Void, Never>?
    private var reloadGeneration = 0
    private let isUITesting: Bool

    var activeListTitle: String {
        if isUITesting {
            return reminderLists.first?.title ?? "Inbox"
        }

        guard access.state == .authorized else {
            return "Inbox"
        }

        return eventKit.defaultCalendar(for: .reminder)?.title ?? "Inbox"
    }

    var reminderListTitles: [String] {
        reminderLists.map(\.title)
    }

    private var eventStore: EKEventStore {
        eventKit.eventStore
    }

    init(eventKit: EventKitService) {
        self.eventKit = eventKit
        access = eventKit.reminderAccess
        isUITesting = eventKit.mode == .uiTesting

        if isUITesting {
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

        changeSubscription = eventKit.changes.sink { [weak self] in
            Task { @MainActor in
                self?.scheduleReloadAfterExternalChange()
            }
        }
    }

    deinit {
        scheduledReloadTask?.cancel()
    }

    func bootstrap() async {
        guard !isUITesting else {
            return
        }

        await access.requestIfNeeded()
        await reload()
    }

    @discardableResult
    func performAccessAction() async -> EventKitAccessAction {
        let action = await access.performAvailableAction()

        if action == .request {
            await reload()
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

        guard access.refresh() == .authorized else {
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
            errorMessage = access.state.saveErrorMessage
            return false
        }

        isSaving = true
        defer { isSaving = false }

        do {
            let calendar = try writableCalendar(for: request)
            let reminder = EKReminder(eventStore: eventStore)
            ReminderEventKitMapper.populate(reminder, from: request, calendar: calendar)

            try eventStore.save(reminder, commit: true)
            do {
                try ReminderKitMetadataWriter.apply(request, to: reminder)
            } catch {
                let metadataError = error

                do {
                    try eventStore.remove(reminder, commit: true)
                } catch {
                    throw ReminderStoreError.nativeMetadataRollbackFailed(
                        metadataError: metadataError.localizedDescription,
                        rollbackError: error.localizedDescription
                    )
                }

                throw ReminderStoreError.nativeMetadataSaveFailed(
                    metadataError.localizedDescription
                )
            }
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
        suppressedTokens: [QuickAddSuppressedToken] = []
    ) async -> Bool {
        let fields = QuickAddParser.parse(input, suppressedTokens: suppressedTokens)
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
            recurrence: fields.recurrence,
            earlyReminder: fields.earlyReminder,
            url: fields.url,
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
        eventKit.openApp(for: .reminder)
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

        return (try? writableCalendar(for: request))?.title ?? activeListTitle
    }

    func preferredList(for identifier: String?) -> ReminderListInfo? {
        guard let identifier else {
            return reminderLists.first { $0.title == activeListTitle }
        }

        return reminderLists.first { $0.id == identifier }
    }

    private func writableCalendar(for request: ReminderCreationRequest) throws -> EKCalendar {
        if let calendar = eventKit.writableCalendar(for: .reminder, matching: request.destination) {
            return calendar
        }

        if request.destination.isSpecific {
            throw ReminderStoreError.requestedListUnavailable
        }

        throw ReminderStoreError.noWritableList
    }

    private func writableReminderLists() -> [ReminderListInfo] {
        eventKit
            .writableCalendars(for: .reminder)
            .map { ReminderListInfo(id: $0.calendarIdentifier, title: $0.title) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private func ensureAccessForUserAction() async -> Bool {
        await access.requestIfNeeded() == .authorized
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
        guard let listTitle = uiTestingList(for: request)?.title else {
            isSaving = false
            errorMessage = request.destination.isSpecific
                ? ReminderStoreError.requestedListUnavailable.localizedDescription
                : ReminderStoreError.noWritableList.localizedDescription
            return false
        }

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
        CalendarDestinationResolver.resolve(
            request.destination,
            in: reminderLists,
            default: reminderLists.first,
            identifier: \.id,
            title: \.title
        )
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
    case requestedListUnavailable
    case nativeMetadataSaveFailed(String)
    case nativeMetadataRollbackFailed(metadataError: String, rollbackError: String)

    var errorDescription: String? {
        switch self {
        case .noWritableList:
            return "No writable Reminders list is available."
        case .requestedListUnavailable:
            return "The requested Reminders list is unavailable or read-only."
        case let .nativeMetadataSaveFailed(message):
            return "The reminder wasn't added because its native fields could not be saved: \(message)"
        case let .nativeMetadataRollbackFailed(metadataError, rollbackError):
            return "The reminder was added, but its native fields failed (\(metadataError)) and Tally could not remove it (\(rollbackError))."
        }
    }
}

private extension EventKitAccessState {
    var saveErrorMessage: String {
        switch self {
        case .notDetermined, .requesting:
            return "Waiting for Reminders access."
        case .denied:
            return "Reminders access is off. Enable it in System Settings."
        case .authorized:
            return "The reminder could not be saved."
        }
    }
}
