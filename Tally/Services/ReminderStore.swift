import EventKit
import AppKit
import Foundation

@MainActor
final class ReminderStore: ObservableObject {
    enum AccessState: Equatable {
        case unknown
        case requesting
        case authorized
        case denied
    }

    @Published private(set) var accessState: AccessState = .unknown
    @Published private(set) var reminders: [ReminderItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published var errorMessage: String?

    private let eventStore = EKEventStore()
    private var changeObserver: NSObjectProtocol?

    var activeListTitle: String {
        eventStore.defaultCalendarForNewReminders()?.title ?? "Inbox"
    }

    var reminderListTitles: [String] {
        eventStore
            .calendars(for: .reminder)
            .filter(\.allowsContentModifications)
            .map(\.title)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    init() {
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
        await requestAccessIfNeeded()
        await reload()
    }

    func requestAccessIfNeeded() async {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess, .authorized:
            accessState = .authorized
        case .notDetermined:
            accessState = .requesting
            let granted = await requestFullReminderAccess()
            accessState = granted ? .authorized : .denied
        case .denied, .restricted, .writeOnly:
            accessState = .denied
        @unknown default:
            accessState = .denied
        }
    }

    func reload() async {
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

    func addReminder(from input: String, notes: String?) async {
        await requestAccessIfNeeded()

        guard accessState == .authorized else {
            return
        }

        let fields = QuickAddParser.parse(input)
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
            reminder.notes = combinedNotes(userNotes: notes, tags: fields.tags)

            try eventStore.save(reminder, commit: true)
            await reload()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func completeReminder(withID id: String) async {
        await requestAccessIfNeeded()

        guard accessState == .authorized else {
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
        await requestAccessIfNeeded()

        guard accessState == .authorized else {
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

    private func requestFullReminderAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            eventStore.requestFullAccessToReminders { granted, _ in
                continuation.resume(returning: granted)
            }
        }
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
                        listName.replacingOccurrences(of: "_", with: " "),
                        options: [.caseInsensitive, .diacriticInsensitive]
                    ) == .orderedSame
            }) {
            return matchingCalendar
        }

        return eventStore.defaultCalendarForNewReminders()
    }

    private func combinedNotes(userNotes: String?, tags: [String]) -> String? {
        let cleanedUserNotes = userNotes?.trimmingCharacters(in: .whitespacesAndNewlines)
        var parts: [String] = []

        if let cleanedUserNotes, !cleanedUserNotes.isEmpty {
            parts.append(cleanedUserNotes)
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
