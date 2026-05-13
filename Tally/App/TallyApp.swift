import SwiftUI

@main
struct TallyApp: App {
    @StateObject private var reminderStore = ReminderStore()
    @AppStorage("showMenuBarBadge") private var showMenuBarBadge = true
    private let appController = AppController()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView {
                appController.showQuickAddAfterMenuDismissal()
            }
                .environmentObject(reminderStore)
        } label: {
            MenuBarIcon(
                count: reminderStore.reminders.count,
                showsBadge: showMenuBarBadge
            )
            .task {
                appController.configure(reminderStore: reminderStore)
                await reminderStore.bootstrap()
            }
        }

        Settings {
            SettingsView()
                .environmentObject(reminderStore)
                .padding(24)
                .frame(width: 420)
        }
    }
}
