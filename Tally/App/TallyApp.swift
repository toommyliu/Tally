import SwiftUI

@main
struct TallyApp: App {
    @NSApplicationDelegateAdaptor(TallyAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(
                onQuickAddShortcutChange: { shortcut in
                    appDelegate.appController.applyQuickAddShortcut(shortcut)
                },
                onTrayShortcutChange: { shortcut in
                    appDelegate.appController.applyTrayShortcut(shortcut)
                },
                onPermissionRequestComplete: {
                    appDelegate.appController.refocusSettingsAfterPermissionRequest()
                }
            )
                .environmentObject(appDelegate.reminderStore)
                .environmentObject(appDelegate.settingsStore)
                .environmentObject(appDelegate.launchAtLoginController)
        }
    }
}

@MainActor
final class TallyAppDelegate: NSObject, NSApplicationDelegate {
    let reminderStore = ReminderStore()
    let settingsStore = AppSettingsStore()
    let launchAtLoginController = LaunchAtLoginController()
    let appController = AppController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        appController.configure(
            reminderStore: reminderStore,
            settingsStore: settingsStore,
            launchAtLoginController: launchAtLoginController
        )

        Task {
            await reminderStore.bootstrap()
        }
    }
}
