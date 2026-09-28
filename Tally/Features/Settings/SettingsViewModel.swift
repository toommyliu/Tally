import AppKit
import Combine
import Foundation

enum SettingsShortcutKind {
    case quickAdd
    case menuBar
}

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var defaultListIdentifier: String? {
        didSet { settingsStore.defaultListIdentifier = defaultListIdentifier }
    }

    @Published var quickAddBehavior: QuickAddBehavior {
        didSet { settingsStore.quickAddBehavior = quickAddBehavior }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            guard !isRefreshingLaunchAtLogin else {
                return
            }
            launchAtLoginController.setEnabled(launchAtLogin)
            refreshLaunchAtLogin()
        }
    }

    @Published private(set) var accessState: EventKitAccessState
    @Published private(set) var calendarAccessState: EventKitAccessState
    @Published private(set) var reminderLists: [CalendarDestinationInfo]
    @Published private(set) var quickAddShortcut: GlobalShortcut
    @Published private(set) var trayShortcut: GlobalShortcut
    @Published private(set) var quickAddShortcutError: String?
    @Published private(set) var trayShortcutError: String?
    @Published private(set) var requestingAccess: EventKitEntity?

    private let reminderStore: ReminderStore
    private let calendarEventStore: CalendarEventStore
    private let settingsStore: AppSettingsStore
    private let launchAtLoginController: LaunchAtLoginController
    private let onQuickAddShortcutChange: (GlobalShortcut) -> Bool
    private let onTrayShortcutChange: (GlobalShortcut) -> Bool
    private let onPermissionRequestComplete: () -> Void
    private var isRefreshingLaunchAtLogin = false
    private var cancellables: Set<AnyCancellable> = []

    init(
        reminderStore: ReminderStore,
        calendarEventStore: CalendarEventStore,
        settingsStore: AppSettingsStore,
        launchAtLoginController: LaunchAtLoginController,
        onQuickAddShortcutChange: @escaping (GlobalShortcut) -> Bool,
        onTrayShortcutChange: @escaping (GlobalShortcut) -> Bool,
        onPermissionRequestComplete: @escaping () -> Void
    ) {
        self.reminderStore = reminderStore
        self.calendarEventStore = calendarEventStore
        self.settingsStore = settingsStore
        self.launchAtLoginController = launchAtLoginController
        self.onQuickAddShortcutChange = onQuickAddShortcutChange
        self.onTrayShortcutChange = onTrayShortcutChange
        self.onPermissionRequestComplete = onPermissionRequestComplete

        defaultListIdentifier = settingsStore.defaultListIdentifier
        quickAddBehavior = settingsStore.quickAddBehavior
        launchAtLogin = launchAtLoginController.isEnabled
        accessState = reminderStore.access.state
        calendarAccessState = calendarEventStore.accessState
        reminderLists = reminderStore.reminderLists
        quickAddShortcut = settingsStore.quickAddShortcut
        trayShortcut = settingsStore.trayShortcut

        reminderStore.access.$state
            .removeDuplicates()
            .sink { [weak self] state in
                self?.accessState = state
            }
            .store(in: &cancellables)

        calendarEventStore.$accessState
            .removeDuplicates()
            .sink { [weak self] state in
                self?.calendarAccessState = state
            }
            .store(in: &cancellables)

        reminderStore.$reminderLists
            .removeDuplicates()
            .sink { [weak self] lists in
                self?.reminderLists = lists
            }
            .store(in: &cancellables)
    }

    var launchAtLoginError: String? {
        launchAtLoginController.errorMessage
    }

    func accessState(for entity: EventKitEntity) -> EventKitAccessState {
        switch entity {
        case .reminder:
            return accessState
        case .event:
            return calendarAccessState
        }
    }

    var defaultListTitle: String {
        guard let defaultListIdentifier else {
            return "System default"
        }

        return reminderLists.first { $0.id == defaultListIdentifier }?.title
            ?? "Unavailable list"
    }

    func refresh() {
        accessState = reminderStore.access.refresh()
        calendarEventStore.reloadCalendars()
        calendarAccessState = calendarEventStore.accessState
        reminderLists = reminderStore.reminderLists
        refreshLaunchAtLogin()
    }

    func chooseDefaultList(_ identifier: String?) {
        defaultListIdentifier = identifier
    }

    func performAccessAction(for entity: EventKitEntity) {
        guard requestingAccess == nil else {
            return
        }

        let action = accessState(for: entity).availableAction
        switch action {
        case .request:
            requestingAccess = entity
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                await performStoreAccessAction(for: entity)
                requestingAccess = nil
                onPermissionRequestComplete()
            }
        case .openSystemSettings:
            Task { @MainActor [weak self] in
                await self?.performStoreAccessAction(for: entity)
            }
        case .none:
            break
        }
    }

    private func performStoreAccessAction(for entity: EventKitEntity) async {
        switch entity {
        case .reminder:
            await reminderStore.performAccessAction()
        case .event:
            await calendarEventStore.performAccessAction()
        }
    }

    func recordShortcut(_ kind: SettingsShortcutKind, from event: NSEvent) {
        guard let candidate = GlobalShortcut.candidate(from: event) else {
            setShortcutError(
                "Press a printable key with Command, Control, or Option.",
                for: kind
            )
            return
        }

        applyShortcut(candidate, kind: kind)
    }

    func resetShortcut(_ kind: SettingsShortcutKind) {
        switch kind {
        case .quickAdd:
            applyShortcut(.defaultQuickAddValue, kind: kind)
        case .menuBar:
            applyShortcut(.defaultTrayValue, kind: kind)
        }
    }

    private func applyShortcut(_ shortcut: GlobalShortcut, kind: SettingsShortcutKind) {
        let didApply: Bool
        switch kind {
        case .quickAdd:
            didApply = onQuickAddShortcutChange(shortcut)
        case .menuBar:
            didApply = onTrayShortcutChange(shortcut)
        }

        guard didApply else {
            setShortcutError("Shortcut is already in use.", for: kind)
            return
        }

        switch kind {
        case .quickAdd:
            settingsStore.quickAddShortcut = shortcut
            quickAddShortcut = shortcut
            quickAddShortcutError = nil
        case .menuBar:
            settingsStore.trayShortcut = shortcut
            trayShortcut = shortcut
            trayShortcutError = nil
        }
    }

    private func setShortcutError(_ error: String, for kind: SettingsShortcutKind) {
        switch kind {
        case .quickAdd:
            quickAddShortcutError = error
        case .menuBar:
            trayShortcutError = error
        }
    }

    private func refreshLaunchAtLogin() {
        launchAtLoginController.refresh()
        isRefreshingLaunchAtLogin = true
        launchAtLogin = launchAtLoginController.isEnabled
        isRefreshingLaunchAtLogin = false
        objectWillChange.send()
    }
}

extension EventKitAccessState {
    var settingsStatusTitle: String {
        switch self {
        case .notDetermined:
            return "Required"
        case .requesting:
            return "Requesting…"
        case .authorized:
            return "Allowed"
        case .denied:
            return "Off"
        }
    }

    var settingsStatusSymbol: String {
        switch self {
        case .authorized:
            return "checkmark.circle.fill"
        case .denied:
            return "exclamationmark.circle.fill"
        case .notDetermined, .requesting:
            return "circle.dotted"
        }
    }

    var settingsStatusColor: NSColor {
        switch self {
        case .authorized:
            return .systemGreen
        case .denied:
            return .systemOrange
        case .notDetermined, .requesting:
            return .secondaryLabelColor
        }
    }

    var settingsActionTitle: String? {
        switch availableAction {
        case .request:
            return "Allow Access…"
        case .openSystemSettings:
            return "Privacy Settings…"
        case .none:
            return nil
        }
    }
}
