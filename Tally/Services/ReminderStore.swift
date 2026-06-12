import EventKit
import AppKit
import Foundation

@MainActor
final class ReminderStore: ObservableObject {
    typealias AccessState = ReminderAccessState

    @Published private(set) var accessState: AccessState = .unknown
    @Published private(set) var reminders: [ReminderItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published var errorMessage: String?

    private let eventStore = EKEventStore()
    private let accessController: ReminderAccessController
    private var changeObserver: NSObjectProtocol?

    var activeListTitle: String {
        guard accessState == .authorized else {
            return "Inbox"
        }

        return eventStore.defaultCalendarForNewReminders()?.title ?? "Inbox"
    }

    var reminderListTitles: [String] {
        guard accessState == .authorized else {
            return []
        }

        return eventStore
            .calendars(for: .reminder)
            .filter(\.allowsContentModifications)
            .map(\.title)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    init() {
        accessController = ReminderAccessController(eventStore: eventStore)

        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: eventStore,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.reload()
            }
        }
    }

    deinit {
        if let changeObserver {
            NotificationCenter.default.removeObserver(changeObserver)
        }
    }

    func bootstrap() async {
        refreshAccessState()
        await reload()
    }

    func refreshAccessState() {
        accessState = accessController.currentState()
    }

    func requestAccess() async {
        let currentState = accessController.currentState()

        guard currentState == .notDetermined else {
            accessState = currentState
            return
        }

        accessState = .requesting
        accessState = await accessController.requestAccessIfNeeded()
    }

    func refreshAccessAfterUserRequest() async {
        if accessState == .authorized {
            refreshAccessState()
        } else {
            await requestAccess()
        }

        await reload()
    }

    func reload() async {
        refreshAccessState()

        guard accessState == .authorized else {
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let fetchedReminders = try await fetchIncompleteReminders()
            reminders = fetchedReminders
                .map(ReminderItem.init(reminder:))
                .sorted(by: ReminderStore.sortReminders)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addReminder(
        from input: String,
        notes: String?,
        suppressedInferredTokens: [QuickAddSuppressedToken] = []
    ) async {
        guard await ensureAccessForUserAction() else {
            return
        }

        let fields = QuickAddParser.parse(input, suppressedInferredTokens: suppressedInferredTokens)
        guard !fields.title.isEmpty else {
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            let reminder = EKReminder(eventStore: eventStore)
            reminder.title = fields.title
            reminder.calendar = writableCalendar(named: fields.listName)
            reminder.priority = fields.priority
            reminder.dueDateComponents = fields.dueDate
            reminder.notes = combinedNotes(userNotes: notes, inlineNotes: fields.inlineNotes, tags: fields.tags)

            try eventStore.save(reminder, commit: true)
            await reload()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func completeReminder(withID id: String) async {
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

    private func writableCalendar(named listName: String?) -> EKCalendar? {
        if let listName,
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

        return eventStore.defaultCalendarForNewReminders()
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

    private func combinedNotes(userNotes: String?, inlineNotes: String?, tags: [String]) -> String? {
        let cleanedUserNotes = userNotes?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedInlineNotes = inlineNotes?.trimmingCharacters(in: .whitespacesAndNewlines)
        var parts: [String] = []

        if let cleanedUserNotes, !cleanedUserNotes.isEmpty {
            parts.append(cleanedUserNotes)
        }

        if let cleanedInlineNotes, !cleanedInlineNotes.isEmpty {
            parts.append(cleanedInlineNotes)
        }

        if !tags.isEmpty {
            parts.append("Tags: " + tags.map { "@\($0)" }.joined(separator: " "))
        }

        return parts.isEmpty ? nil : parts.joined(separator: "\n")
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
