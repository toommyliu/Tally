import AppKit

@MainActor
final class AppController: NSObject {
    private static let menuDismissalDelayNanoseconds: UInt64 = 120_000_000

    private var didConfigure = false
    private var quickAddHotKeyController: HotKeyController?
    private var trayHotKeyController: HotKeyController?
    private var menuBarController: MenuBarController?
    private var quickAddWindowController: QuickAddWindowController?
    private var settingsWindowController: SettingsWindowController?

    func configure(
        reminderStore: ReminderStore,
        settingsStore: AppSettingsStore,
        launchAtLoginController: LaunchAtLoginController
    ) {
        guard !didConfigure else {
            return
        }

        let quickAddWindowController = QuickAddWindowController(
            reminderStore: reminderStore,
            settingsStore: settingsStore
        )
        let menuBarController = MenuBarController(
            reminderStore: reminderStore,
            settingsStore: settingsStore,
            appController: self
        )
        let settingsWindowController = SettingsWindowController(
            reminderStore: reminderStore,
            settingsStore: settingsStore,
            launchAtLoginController: launchAtLoginController
        )
        let quickAddHotKeyController = HotKeyController(
            id: 1,
            shortcut: settingsStore.quickAddShortcut
        ) { [weak self] in
            self?.showQuickAdd()
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

        settingsWindowController.onQuickAddShortcutChange = { [weak quickAddHotKeyController] shortcut in
            quickAddHotKeyController?.applyShortcut(shortcut) ?? false
        }
        settingsWindowController.onTrayShortcutChange = { [weak trayHotKeyController] shortcut in
            trayHotKeyController?.applyShortcut(shortcut) ?? false
        }
        settingsWindowController.onReturnToMenu = { [weak menuBarController] in
            menuBarController?.toggleTrayVisibility()
        }

        self.quickAddWindowController = quickAddWindowController
        self.menuBarController = menuBarController
        self.settingsWindowController = settingsWindowController
        self.quickAddHotKeyController = quickAddHotKeyController
        self.trayHotKeyController = trayHotKeyController
        didConfigure = true
    }

    func showQuickAdd() {
        // Capture before Tally activates so `main` still reflects the
        // source app's focused window.
        showQuickAdd(on: NSScreen.main)
    }

    private func showQuickAdd(on targetScreen: NSScreen?) {
        if settingsWindowController?.isPresented == true {
            settingsWindowController?.dismiss { [weak self] in
                self?.quickAddWindowController?.show(on: targetScreen)
            }
        } else {
            quickAddWindowController?.show(on: targetScreen)
        }
    }

    func showQuickAddAfterMenuDismissal() {
        let targetScreen = NSScreen.main
        performAfterMenuDismissal { [weak self] in
            self?.showQuickAdd(on: targetScreen)
        }
    }

    func showSettingsAfterMenuDismissal() {
        performAfterMenuDismissal { [weak self] in
            guard let self else {
                return
            }

            NSApp.activate(ignoringOtherApps: true)
            settingsWindowController?.present(anchoredTo: menuBarController?.settingsAnchorView)
        }
    }

    func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        settingsWindowController?.present()
    }

    func prepareForTermination() {
        settingsWindowController?.closeBeforeTermination()
    }

    private func performAfterMenuDismissal(_ action: @escaping () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.menuDismissalDelayNanoseconds)
            guard !Task.isCancelled else {
                return
            }

            action()
        }
    }
}
