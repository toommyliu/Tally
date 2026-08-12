import Foundation

@MainActor
final class AppSettingsStore: ObservableObject {
    let quickAddWindowPositionStore: QuickAddWindowPositionStore

    @Published var quickAddShortcut: GlobalShortcut {
        didSet {
            Self.persist(quickAddShortcut, to: userDefaults, forKey: Keys.quickAddShortcut)
        }
    }

    @Published var trayShortcut: GlobalShortcut {
        didSet {
            Self.persist(trayShortcut, to: userDefaults, forKey: Keys.trayShortcut)
        }
    }

    @Published var defaultListIdentifier: String? {
        didSet {
            if let defaultListIdentifier {
                userDefaults.set(defaultListIdentifier, forKey: Keys.defaultListIdentifier)
            } else {
                userDefaults.removeObject(forKey: Keys.defaultListIdentifier)
            }
        }
    }

    @Published var quickAddBehavior: QuickAddBehavior {
        didSet {
            userDefaults.set(quickAddBehavior.rawValue, forKey: Keys.quickAddBehavior)
        }
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults? = nil) {
        let userDefaults = userDefaults ?? Self.defaultUserDefaults()
        self.userDefaults = userDefaults
        self.quickAddWindowPositionStore = QuickAddWindowPositionStore(
            userDefaults: userDefaults
        )

        self.quickAddShortcut = Self.loadShortcut(
            forKey: Keys.quickAddShortcut,
            from: userDefaults,
            defaultValue: .defaultQuickAddValue
        )
        self.trayShortcut = Self.loadShortcut(
            forKey: Keys.trayShortcut,
            from: userDefaults,
            defaultValue: .defaultTrayValue
        )
        self.defaultListIdentifier = userDefaults.string(forKey: Keys.defaultListIdentifier)

        if let rawBehavior = userDefaults.string(forKey: Keys.quickAddBehavior),
           let behavior = QuickAddBehavior(rawValue: rawBehavior) {
            self.quickAddBehavior = behavior
        } else {
            self.quickAddBehavior = .closeAfterAdding
        }

    }

    private static func defaultUserDefaults() -> UserDefaults {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            let suiteName = "Tally.UITesting"
            let userDefaults = UserDefaults(suiteName: suiteName) ?? .standard
            userDefaults.removePersistentDomain(forName: suiteName)
            return userDefaults
        }
        #endif

        return .standard
    }

    private static func loadShortcut(
        forKey key: String,
        from userDefaults: UserDefaults,
        defaultValue: GlobalShortcut
    ) -> GlobalShortcut {
        guard let data = userDefaults.data(forKey: key) else {
            persist(defaultValue, to: userDefaults, forKey: key)
            return defaultValue
        }

        guard let shortcut = try? JSONDecoder().decode(GlobalShortcut.self, from: data) else {
            return .invalidValue
        }

        return shortcut
    }

    private static func persist(_ shortcut: GlobalShortcut, to userDefaults: UserDefaults, forKey key: String) {
        guard shortcut.isValid,
              let encoded = try? JSONEncoder().encode(shortcut)
        else {
            return
        }

        userDefaults.set(encoded, forKey: key)
    }

    private enum Keys {
        static let quickAddShortcut = "QuickAddShortcut"
        static let trayShortcut = "TrayShortcut"
        static let defaultListIdentifier = "DefaultReminderListIdentifier"
        static let quickAddBehavior = "QuickAddBehavior"
    }
}
