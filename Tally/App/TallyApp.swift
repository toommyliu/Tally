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
    let eventKit = EventKitService()
    lazy var reminderStore = ReminderStore(eventKit: eventKit)
    lazy var calendarEventStore = CalendarEventStore(eventKit: eventKit)
    let settingsStore = AppSettingsStore()
    let launchAtLoginController = LaunchAtLoginController()
    let appController = AppController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Each test build has a new code signature, so a TCC request here prompts on every run
        // and an approval replaces the installed app's Reminders grant.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return
        }

        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--native-self-test") {
            guard arguments.indices.contains(index + 1) else {
                exit(1)
            }
            Task {
                await NativeReminderSelfTest.run(outputFileName: arguments[index + 1])
            }
            return
        }
        #endif

        appController.configure(
            reminderStore: reminderStore,
            calendarEventStore: calendarEventStore,
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
