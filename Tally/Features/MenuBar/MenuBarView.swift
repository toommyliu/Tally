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

struct SettingsView: View {
    @EnvironmentObject private var reminderStore: ReminderStore
    @AppStorage("showMenuBarBadge") private var showMenuBarBadge = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tally")
                .font(.title2.bold())

            Text("Uses Apple Reminders through EventKit. Changes made in Reminders, Calendar, iCloud, or other apps refresh automatically when EventKit posts a store-change notification.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Refresh Reminders") {
                Task {
                    await reminderStore.reload()
                }
            }

            Toggle("Show reminder count badge in menu bar", isOn: $showMenuBarBadge)
        }
    }
}
