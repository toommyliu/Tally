import AppKit
import Combine
import SwiftUI

@MainActor
final class MenuBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let reminderStore: ReminderStore
    private let settingsStore: AppSettingsStore
    private let appController: AppController
    private var cancellables: Set<AnyCancellable> = []
    private var isTrayMenuOpen = false
    private var trayMenuKeyMonitor: Any?

    var onTrayMenuWillOpen: (() -> Void)?
    var onTrayMenuDidClose: (() -> Void)?

    init(
        reminderStore: ReminderStore,
        settingsStore: AppSettingsStore,
        appController: AppController
    ) {
        self.reminderStore = reminderStore
        self.settingsStore = settingsStore
        self.appController = appController
        super.init()
        configure()
    }

    func toggleTrayVisibility() {
        if isTrayMenuOpen {
            statusItem.menu?.cancelTracking()
            return
        }

        statusItem.button?.performClick(nil)
    }

    private func configure() {
        statusItem.button?.toolTip = "Tally"
        refreshStatusItem()
        refreshMenu()

        reminderStore.$reminders
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshStatusItem()
                self?.refreshMenu()
            }
            .store(in: &cancellables)

        settingsStore.$badgeStyle
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshStatusItem()
            }
            .store(in: &cancellables)

        settingsStore.$trayShortcut
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshMenu()
            }
            .store(in: &cancellables)
    }

    private func refreshStatusItem() {
        let count = reminderStore.reminders.count

        switch settingsStore.badgeStyle {
        case .trailingCount:
            statusItem.length = NSStatusItem.variableLength
            statusItem.button?.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "Tally")
            statusItem.button?.imageScaling = .scaleNone
            statusItem.button?.imagePosition = .imageLeading
            statusItem.button?.title = count > 0 ? " \(count)" : ""
        case .iconBadge:
            statusItem.length = MenuBarIconRenderer.statusItemLength
            statusItem.button?.image = MenuBarIconRenderer.image(count: count)
            statusItem.button?.imageScaling = .scaleNone
            statusItem.button?.imagePosition = .imageOnly
            statusItem.button?.title = ""
        }
    }

    private func refreshMenu() {
        let menu = TrayMenu()
        menu.delegate = self

        let quickAddItem = NSMenuItem(title: "Quick Add", action: #selector(showQuickAdd), keyEquivalent: " ")
        quickAddItem.keyEquivalentModifierMask = [.option]
        quickAddItem.target = self
        menu.addItem(quickAddItem)

        menu.addItem(.separator())

        if reminderStore.reminders.isEmpty {
            let emptyItem = NSMenuItem(title: "No open reminders", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            for reminder in reminderStore.reminders.prefix(10) {
                let item = NSMenuItem(title: reminder.menuTitle, action: #selector(openReminder(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = reminder.id
                item.submenu = reminderActionsMenu(for: reminder)
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        let openRemindersItem = NSMenuItem(title: "Open Reminders", action: #selector(openReminders), keyEquivalent: "r")
        openRemindersItem.keyEquivalentModifierMask = [.command]
        openRemindersItem.target = self
        menu.addItem(openRemindersItem)

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.keyEquivalentModifierMask = [.command]
        settingsItem.target = self
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(title: "Quit Tally", action: #selector(quit), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = [.command]
        quitItem.target = self
        menu.addItem(quitItem)

        let closeItem = NSMenuItem(title: "Close Menu", action: #selector(closeTrayMenu), keyEquivalent: settingsStore.trayShortcut.keyEquivalent)
        closeItem.keyEquivalentModifierMask = settingsStore.trayShortcut.menuModifierFlags
        closeItem.target = self
        closeItem.isHidden = true
        closeItem.allowsKeyEquivalentWhenHidden = true
        menu.addItem(closeItem)

        statusItem.menu = menu
    }

    private func reminderActionsMenu(for reminder: ReminderItem) -> NSMenu {
        let menu = NSMenu()

        let openItem = NSMenuItem(title: "Open in Reminders", action: #selector(openReminder(_:)), keyEquivalent: "")
        openItem.target = self
        openItem.representedObject = reminder.id
        menu.addItem(openItem)

        let completeItem = NSMenuItem(title: "Complete", action: #selector(completeReminder(_:)), keyEquivalent: "")
        completeItem.target = self
        completeItem.representedObject = reminder.id
        menu.addItem(completeItem)

        let deleteItem = NSMenuItem(title: "Delete", action: #selector(deleteReminder(_:)), keyEquivalent: "")
        deleteItem.target = self
        deleteItem.representedObject = reminder.id
        menu.addItem(deleteItem)

        return menu
    }

    @objc private func showQuickAdd() {
        appController.showQuickAddAfterMenuDismissal()
    }

    @objc private func openReminder(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String {
            reminderStore.openReminder(withID: id)
        } else {
            reminderStore.openReminders()
        }
    }

    @objc private func completeReminder(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else {
            return
        }

        Task {
            await reminderStore.completeReminder(withID: id)
        }
    }

    @objc private func deleteReminder(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else {
            return
        }

        Task {
            await reminderStore.deleteReminder(withID: id)
        }
    }

    @objc private func openReminders() {
        reminderStore.openReminders()
    }

    @objc private func openSettings() {
        appController.showSettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func closeTrayMenu() {
        statusItem.menu?.cancelTracking()
    }
}

extension MenuBarController: NSMenuDelegate {
    nonisolated func menuWillOpen(_ menu: NSMenu) {
        updateTrayMenuOpenState(true, menu: menu)
    }

    nonisolated func menuDidClose(_ menu: NSMenu) {
        updateTrayMenuOpenState(false, menu: menu)
    }

    private nonisolated func updateTrayMenuOpenState(_ isOpen: Bool, menu: NSMenu) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                setTrayMenuOpenState(isOpen, menu: menu)
            }
        } else {
            Task { @MainActor in
                setTrayMenuOpenState(isOpen, menu: menu)
            }
        }
    }

    private func setTrayMenuOpenState(_ isOpen: Bool, menu: NSMenu) {
        isTrayMenuOpen = isOpen

        if isOpen {
            installTrayMenuKeyMonitor(for: menu)
            onTrayMenuWillOpen?()
        } else {
            removeTrayMenuKeyMonitor()
            onTrayMenuDidClose?()
            refreshMenu()
        }
    }

    private func installTrayMenuKeyMonitor(for menu: NSMenu) {
        removeTrayMenuKeyMonitor()
        trayMenuKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak menu] event in
            guard let trayMenu = menu as? TrayMenu,
                  trayMenu.performTrackedKeyEquivalent(with: event)
            else {
                return event
            }

            return nil
        }
    }

    private func removeTrayMenuKeyMonitor() {
        guard let trayMenuKeyMonitor else {
            return
        }

        NSEvent.removeMonitor(trayMenuKeyMonitor)
        self.trayMenuKeyMonitor = nil
    }
}

private final class TrayMenu: NSMenu {
    fileprivate static let significantModifierFlags: NSEvent.ModifierFlags = [.command, .control, .option, .shift]

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        performTrackedKeyEquivalent(with: event)
    }

    func performTrackedKeyEquivalent(with event: NSEvent) -> Bool {
        if let item = items.first(where: { $0.matchesKeyEquivalent(event) }) {
            cancelTracking()
            performAction(for: item)
            return true
        }

        if items.contains(where: { $0.hasKeyEquivalentKey(for: event) }) {
            return false
        }

        return super.performKeyEquivalent(with: event)
    }

    private func performAction(for item: NSMenuItem) {
        guard let action = item.action else {
            return
        }

        NSApp.sendAction(action, to: item.target, from: item)
    }
}

private extension NSMenuItem {
    func hasKeyEquivalentKey(for event: NSEvent) -> Bool {
        event.type == .keyDown
            && !keyEquivalent.isEmpty
            && event.charactersIgnoringModifiers?.lowercased() == keyEquivalent.lowercased()
    }

    func matchesKeyEquivalent(_ event: NSEvent) -> Bool {
        guard hasKeyEquivalentKey(for: event),
              isEnabled,
              (!isHidden || allowsKeyEquivalentWhenHidden),
              action != nil
        else {
            return false
        }

        let eventFlags = event.modifierFlags.intersection(TrayMenu.significantModifierFlags)
        let itemFlags = keyEquivalentModifierMask.intersection(TrayMenu.significantModifierFlags)
        return eventFlags == itemFlags
    }
}

private extension ReminderItem {
    var menuTitle: String {
        if let dueDate {
            return "\(title) - \(dueDate.shortDisplayTitle)"
        }

        return title
    }
}
