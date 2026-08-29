import AppKit
import Combine

@MainActor
final class MenuBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: MenuBarStatusView.minimumStatusItemLength)
    private let statusView = MenuBarStatusView()
    private let reminderStore: ReminderStore
    private let settingsStore: AppSettingsStore
    private weak var appController: AppController?
    private var cancellables: Set<AnyCancellable> = []
    private var isTrayMenuOpen = false
    private var trayMenuKeyMonitor: Any?
    private var lastStatusItemCount: Int?

    var onTrayMenuWillOpen: (() -> Void)?
    var onTrayMenuDidClose: (() -> Void)?

    var settingsAnchorView: NSView? {
        statusItem.button
    }

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
        configureStatusButton()
        refreshStatusItem()
        refreshMenu()

        reminderStore.$reminders
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshStatusItem()
                self?.refreshMenu()
            }
            .store(in: &cancellables)

        reminderStore.$accessState
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshMenu()
            }
            .store(in: &cancellables)

        reminderStore.$isLoading
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshMenu()
            }
            .store(in: &cancellables)

        reminderStore.$errorMessage
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshMenu()
            }
            .store(in: &cancellables)

        settingsStore.$quickAddShortcut
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshMenu()
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

        if lastStatusItemCount != count {
            statusItem.length = MenuBarStatusView.statusItemLength(for: count)
            lastStatusItemCount = count
        }

        statusView.update(count: count)
        let statusDescription = count == 1
            ? "Tally — 1 open reminder"
            : "Tally — \(count) open reminders"
        statusItem.button?.toolTip = statusDescription
        statusItem.button?.setAccessibilityLabel(statusDescription)
    }

    private func configureStatusButton() {
        guard let button = statusItem.button else {
            return
        }

        statusItem.length = MenuBarStatusView.minimumStatusItemLength
        button.image = nil
        button.title = ""
        button.imagePosition = .noImage

        statusView.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(statusView)

        NSLayoutConstraint.activate([
            statusView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            statusView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            statusView.topAnchor.constraint(equalTo: button.topAnchor),
            statusView.bottomAnchor.constraint(equalTo: button.bottomAnchor)
        ])
    }

    private func refreshMenu() {
        let menu = TrayMenu()
        menu.delegate = self

        let quickAddItem = NSMenuItem(
            title: "Quick Add",
            action: #selector(showQuickAdd),
            keyEquivalent: settingsStore.quickAddShortcut.keyEquivalent
        )
        quickAddItem.keyEquivalentModifierMask = settingsStore.quickAddShortcut.menuModifierFlags
        quickAddItem.target = self
        quickAddItem.isEnabled = settingsStore.quickAddShortcut.isValid
        menu.addItem(quickAddItem)

        menu.addItem(.separator())

        if reminderStore.accessState != .authorized {
            let accessItem = NSMenuItem(title: reminderStore.accessState.menuTitle, action: nil, keyEquivalent: "")
            accessItem.isEnabled = false
            menu.addItem(accessItem)

            if let actionTitle = reminderStore.accessState.menuActionTitle {
                let accessActionItem = NSMenuItem(
                    title: actionTitle,
                    action: #selector(performRemindersAccessAction),
                    keyEquivalent: ""
                )
                accessActionItem.target = self
                menu.addItem(accessActionItem)
            }
        } else if reminderStore.isLoading {
            let loadingItem = NSMenuItem(title: "Syncing reminders...", action: nil, keyEquivalent: "")
            loadingItem.isEnabled = false
            menu.addItem(loadingItem)
        } else if let errorMessage = reminderStore.errorMessage {
            let errorItem = NSMenuItem(title: "Sync error: \(errorMessage)".truncatedForMenu(maxLength: 30), action: nil, keyEquivalent: "")
            errorItem.isEnabled = false
            menu.addItem(errorItem)

            let retryItem = NSMenuItem(title: "Retry Sync", action: #selector(refreshReminders), keyEquivalent: "")
            retryItem.target = self
            menu.addItem(retryItem)
        } else if reminderStore.reminders.isEmpty {
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

        let openItem = NSMenuItem(title: "Open in Reminders", action: #selector(openReminder(_:)), keyEquivalent: "1")
        openItem.keyEquivalentModifierMask = []
        openItem.target = self
        openItem.representedObject = reminder.id
        menu.addItem(openItem)

        let completeItem = NSMenuItem(title: "Complete", action: #selector(completeReminder(_:)), keyEquivalent: "2")
        completeItem.keyEquivalentModifierMask = []
        completeItem.target = self
        completeItem.representedObject = reminder.id
        menu.addItem(completeItem)

        let deleteItem = NSMenuItem(title: "Delete", action: #selector(deleteReminder(_:)), keyEquivalent: "3")
        deleteItem.keyEquivalentModifierMask = []
        deleteItem.target = self
        deleteItem.representedObject = reminder.id
        menu.addItem(deleteItem)

        return menu
    }

    @objc private func showQuickAdd() {
        appController?.showQuickAddAfterMenuDismissal()
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

    @objc private func refreshReminders() {
        Task {
            await reminderStore.reload()
        }
    }

    @objc private func performRemindersAccessAction() {
        Task {
            await reminderStore.performAccessAction()
        }
    }

    @objc private func openSettings() {
        appController?.showSettingsAfterMenuDismissal()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func closeTrayMenu() {
        statusItem.menu?.cancelTracking()
    }
}

private extension ReminderStore.AccessState {
    var menuTitle: String {
        switch self {
        case .unknown:
            return "Checking Reminders access..."
        case .notDetermined:
            return "Tally needs Reminders access"
        case .requesting:
            return "Waiting for Reminders access..."
        case .authorized:
            return "Reminders ready"
        case .denied:
            return "Reminders access is off"
        }
    }

    var menuActionTitle: String? {
        switch availableAction {
        case .request:
            return "Allow Reminders Access..."
        case .openSystemSettings:
            return "Open System Settings..."
        case .none:
            return nil
        }
    }
}

private final class MenuBarStatusView: NSView {
    static let minimumStatusItemLength: CGFloat = 28

    private let imageView = NSImageView()
    private var count: Int = 0

    private static let horizontalPadding: CGFloat = 4
    private static let iconWidth: CGFloat = 20
    private static let iconHeight: CGFloat = 18
    private static let iconCountSpacing: CGFloat = 4

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureImageView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureImageView()
    }

    static func statusItemLength(for count: Int) -> CGFloat {
        guard count > 0 else {
            return minimumStatusItemLength
        }

        let countWidth = iconWidth + iconCountSpacing + countTextSize(for: count).width
        return ceil(max(minimumStatusItemLength, countWidth + horizontalPadding * 2))
    }

    func update(count: Int) {
        self.count = count
        needsLayout = true
        needsDisplay = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func layout() {
        super.layout()
        imageView.frame = Self.iconRect(count: count, bounds: bounds)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard count > 0 else {
            return
        }

        let iconRect = Self.iconRect(count: count, bounds: bounds)
        Self.drawTrailingCount(count, after: iconRect)
    }

    private func configureImageView() {
        imageView.image = .tallyMenuCheckmark
        imageView.imageScaling = .scaleProportionallyDown
        imageView.contentTintColor = .labelColor
        imageView.setAccessibilityElement(false)
        imageView.translatesAutoresizingMaskIntoConstraints = true
        addSubview(imageView)
    }

    private static func iconRect(count: Int, bounds: NSRect) -> NSRect {
        NSRect(
            x: iconOriginX(count: count, viewWidth: bounds.width),
            y: floor((bounds.height - iconHeight) / 2),
            width: iconWidth,
            height: iconHeight
        )
    }

    private static func iconOriginX(count: Int, viewWidth: CGFloat) -> CGFloat {
        guard count > 0 else {
            return floor((viewWidth - iconWidth) / 2)
        }

        let contentWidth = iconWidth + iconCountSpacing + countTextSize(for: count).width
        return floor((viewWidth - contentWidth) / 2)
    }

    private static func drawTrailingCount(_ count: Int, after iconRect: NSRect) {
        let attributedText = NSAttributedString(string: countText(for: count), attributes: countTextAttributes)
        let textSize = attributedText.size()
        attributedText.draw(at: NSPoint(
            x: iconRect.maxX + iconCountSpacing,
            y: floor(iconRect.midY - textSize.height / 2)
        ))
    }

    private static func countText(for count: Int) -> String {
        count > 99 ? "99+" : "\(count)"
    }

    private static func countTextSize(for count: Int) -> NSSize {
        NSAttributedString(string: countText(for: count), attributes: countTextAttributes).size()
    }

    private static var countTextAttributes: [NSAttributedString.Key: Any] {
        [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .medium),
            .foregroundColor: NSColor.labelColor.withAlphaComponent(0.90)
        ]
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

        if let item = highlightedSubmenuItem(matching: event) {
            cancelTracking()
            performAction(for: item)
            return true
        }

        if hasSubmenuKeyEquivalent(for: event) {
            return false
        }

        return super.performKeyEquivalent(with: event)
    }

    private func highlightedSubmenuItem(matching event: NSEvent) -> NSMenuItem? {
        highlightedItem?
            .submenu?
            .items
            .first(where: { $0.matchesKeyEquivalent(event) })
    }

    private func hasSubmenuKeyEquivalent(for event: NSEvent) -> Bool {
        items.contains { item in
            item.submenu?.items.contains { $0.hasKeyEquivalentKey(for: event) } ?? false
        }
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
