import AppKit

@MainActor
final class AppController {
    private var didConfigure = false
    private var quickAddHotKeyController: HotKeyController?
    private var trayHotKeyController: HotKeyController?
    private var menuBarController: MenuBarController?
    private var quickAddWindowController: QuickAddWindowController?

    func configure(
        reminderStore: ReminderStore,
        settingsStore: AppSettingsStore,
        launchAtLoginController: LaunchAtLoginController
    ) {
        guard !didConfigure else {
            return
        }

        let quickAddWindowController = QuickAddWindowController(reminderStore: reminderStore)
        let menuBarController = MenuBarController(
            reminderStore: reminderStore,
            settingsStore: settingsStore,
            appController: self
        )
        let quickAddHotKeyController = HotKeyController(
            id: 1,
            shortcut: settingsStore.quickAddShortcut
        ) { [weak quickAddWindowController] in
            quickAddWindowController?.show()
        }
        let trayHotKeyController = HotKeyController(
            id: 2,
            shortcut: settingsStore.trayShortcut
        ) { [weak menuBarController] in
            menuBarController?.toggleTrayVisibility()
        }

        menuBarController.onTrayMenuWillOpen = { [weak trayHotKeyController] in
            trayHotKeyController?.setEnabled(false)
        }
        menuBarController.onTrayMenuDidClose = { [weak trayHotKeyController] in
            trayHotKeyController?.setEnabled(true)
        }

        self.quickAddWindowController = quickAddWindowController
        self.menuBarController = menuBarController
        self.quickAddHotKeyController = quickAddHotKeyController
        self.trayHotKeyController = trayHotKeyController
        didConfigure = true
    }

    func applyQuickAddShortcut(_ shortcut: GlobalShortcut) -> Bool {
        quickAddHotKeyController?.applyShortcut(shortcut) ?? false
    }

    func applyTrayShortcut(_ shortcut: GlobalShortcut) -> Bool {
        trayHotKeyController?.applyShortcut(shortcut) ?? false
    }

    func showQuickAdd() {
        quickAddWindowController?.show()
    }

    func showQuickAddAfterMenuDismissal() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            quickAddWindowController?.show()
        }
    }

    func showSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}
