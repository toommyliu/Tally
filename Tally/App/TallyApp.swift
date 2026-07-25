import SwiftUI

@main
struct TallyApp: App {
    @NSApplicationDelegateAdaptor(TallyAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    appDelegate.appController.showSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
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
            #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("--show-quick-add") {
                appController.showQuickAdd()
            } else if arguments.contains("--show-settings") {
                appController.showSettings()
            }
            #endif

            await reminderStore.bootstrap()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        appController.prepareForTermination()
    }
}
