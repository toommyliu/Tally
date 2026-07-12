import AppKit
import SwiftUI

@MainActor
final class AppController: NSObject, NSWindowDelegate {
    private static let menuDismissalDelayNanoseconds: UInt64 = 120_000_000

    private var didConfigure = false
    private var reminderStore: ReminderStore?
    private var settingsStore: AppSettingsStore?
    private var launchAtLoginController: LaunchAtLoginController?
    private var quickAddHotKeyController: HotKeyController?
    private var trayHotKeyController: HotKeyController?
    private var menuBarController: MenuBarController?
    private var quickAddWindowController: QuickAddWindowController?
    private var settingsWindow: NSWindow?

    func configure(
        reminderStore: ReminderStore,
        settingsStore: AppSettingsStore,
        launchAtLoginController: LaunchAtLoginController
    ) {
        guard !didConfigure else {
            return
        }

        self.reminderStore = reminderStore
        self.settingsStore = settingsStore
        self.launchAtLoginController = launchAtLoginController

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
        performAfterMenuDismissal { [weak self] in
            self?.quickAddWindowController?.show()
        }
    }

    func showSettingsAfterMenuDismissal() {
        performAfterMenuDismissal { [weak self] in
            self?.showSettings()
        }
    }

    func showSettings() {
        let shouldCenterWindow = settingsWindow == nil

        if settingsWindow == nil {
            settingsWindow = makeSettingsWindow()
        }

        guard let settingsWindow else {
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        if shouldCenterWindow {
            settingsWindow.center()
        }
        settingsWindow.makeKeyAndOrderFront(nil)
    }

    func refocusSettingsAfterPermissionRequest() {
        NSApp.activate(ignoringOtherApps: true)

        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
        } else {
            NSApp.keyWindow?.makeKeyAndOrderFront(nil)
        }
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

    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === settingsWindow else {
            return
        }

        settingsWindow?.delegate = nil
        settingsWindow?.contentViewController = nil
        settingsWindow = nil
    }

    private func makeSettingsWindow() -> NSWindow? {
        guard let reminderStore,
              let settingsStore,
              let launchAtLoginController
        else {
            return nil
        }

        let contentView = SettingsView(
            onQuickAddShortcutChange: { [weak self] shortcut in
                MainActor.assumeIsolated {
                    self?.applyQuickAddShortcut(shortcut) ?? false
                }
            },
            onTrayShortcutChange: { [weak self] shortcut in
                MainActor.assumeIsolated {
                    self?.applyTrayShortcut(shortcut) ?? false
                }
            },
            onPermissionRequestComplete: { [weak self] in
                MainActor.assumeIsolated {
                    self?.refocusSettingsAfterPermissionRequest()
                }
            }
        )
            .environmentObject(reminderStore)
            .environmentObject(settingsStore)
            .environmentObject(launchAtLoginController)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: SettingsLayout.windowSize),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.contentViewController = NSHostingController.tallyClearBackground(rootView: contentView)
        window.delegate = self
        window.setContentSize(SettingsLayout.windowSize)
        window.contentMinSize = SettingsLayout.windowSize
        window.contentMaxSize = SettingsLayout.windowSize
        window.isReleasedWhenClosed = false
        window.contentView?.prepareForTallyTransparentWindow()
        return window
    }
}
