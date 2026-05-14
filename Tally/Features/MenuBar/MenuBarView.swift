import AppKit
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var reminderStore: ReminderStore
    @AppStorage("showMenuBarBadge") private var showMenuBarBadge = true

    let onQuickAdd: () -> Void

    var body: some View {
        Button("Quick Add", action: onQuickAdd)
            .keyboardShortcut(.space, modifiers: .option)

        Divider()

        Button("Open Reminders") {
            openReminders()
        }

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
    }

    private func openReminders() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.reminders") else {
            return
        }

        NSWorkspace.shared.openApplication(
            at: url,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }
}
