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

    @Published private(set) var accessState: ReminderAccessState
    @Published private(set) var reminderLists: [ReminderListInfo]
    @Published private(set) var quickAddShortcut: GlobalShortcut
    @Published private(set) var trayShortcut: GlobalShortcut
    @Published private(set) var quickAddShortcutError: String?
    @Published private(set) var trayShortcutError: String?
    @Published private(set) var isRequestingAccess = false

    private let reminderStore: ReminderStore
    private let settingsStore: AppSettingsStore
    private let launchAtLoginController: LaunchAtLoginController
    private let onQuickAddShortcutChange: (GlobalShortcut) -> Bool
    private let onTrayShortcutChange: (GlobalShortcut) -> Bool
    private let onPermissionRequestComplete: () -> Void
    private var isRefreshingLaunchAtLogin = false
    private var cancellables: Set<AnyCancellable> = []

    init(
        reminderStore: ReminderStore,
        settingsStore: AppSettingsStore,
        launchAtLoginController: LaunchAtLoginController,
        onQuickAddShortcutChange: @escaping (GlobalShortcut) -> Bool,
        onTrayShortcutChange: @escaping (GlobalShortcut) -> Bool,
        onPermissionRequestComplete: @escaping () -> Void
    ) {
        self.reminderStore = reminderStore
        self.settingsStore = settingsStore
        self.launchAtLoginController = launchAtLoginController
        self.onQuickAddShortcutChange = onQuickAddShortcutChange
        self.onTrayShortcutChange = onTrayShortcutChange
        self.onPermissionRequestComplete = onPermissionRequestComplete

        defaultListIdentifier = settingsStore.defaultListIdentifier
        quickAddBehavior = settingsStore.quickAddBehavior
        launchAtLogin = launchAtLoginController.isEnabled
        accessState = reminderStore.accessState
        reminderLists = reminderStore.reminderLists
        quickAddShortcut = settingsStore.quickAddShortcut
        trayShortcut = settingsStore.trayShortcut

        reminderStore.$accessState
            .removeDuplicates()
            .sink { [weak self] state in
                self?.accessState = state
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

    var accessStatusTitle: String {
        switch accessState {
        case .unknown:
            return "Checking…"
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

    var accessStatusSymbol: String {
        switch accessState {
        case .authorized:
            return "checkmark.circle.fill"
        case .denied:
            return "exclamationmark.circle.fill"
        case .unknown, .notDetermined, .requesting:
            return "circle.dotted"
        }
    }

    var accessStatusColor: NSColor {
        switch accessState {
        case .authorized:
            return .systemGreen
        case .denied:
            return .systemOrange
        case .unknown, .notDetermined, .requesting:
            return .secondaryLabelColor
        }
    }

    var accessActionTitle: String? {
        switch accessState.availableAction {
        case .request:
            return "Allow Access…"
        case .openSystemSettings:
            return "Privacy Settings…"
        case .none:
            return nil
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
        reminderStore.refreshAccessState()
        accessState = reminderStore.accessState
        reminderLists = reminderStore.reminderLists
        refreshLaunchAtLogin()
    }

    func chooseDefaultList(_ identifier: String?) {
        defaultListIdentifier = identifier
    }

    func performAccessAction() {
        guard !isRequestingAccess else {
            return
        }

        let action = accessState.availableAction
        switch action {
        case .request:
            isRequestingAccess = true
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                _ = await reminderStore.performAccessAction()
                isRequestingAccess = false
                onPermissionRequestComplete()
            }
        case .openSystemSettings:
            Task { @MainActor [weak self] in
                _ = await self?.reminderStore.performAccessAction()
            }
        case .none:
            break
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
