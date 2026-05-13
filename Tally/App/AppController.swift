import Foundation

@MainActor
final class AppController {
    private var didConfigure = false
    private var hotKeyController: HotKeyController?
    private var quickAddWindowController: QuickAddWindowController?

    func configure(reminderStore: ReminderStore) {
        guard !didConfigure else {
            return
        }

        let quickAddWindowController = QuickAddWindowController(reminderStore: reminderStore)
        let hotKeyController = HotKeyController { [weak quickAddWindowController] in
            quickAddWindowController?.show()
        }

        hotKeyController.register()

        self.quickAddWindowController = quickAddWindowController
        self.hotKeyController = hotKeyController
        didConfigure = true
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
}
