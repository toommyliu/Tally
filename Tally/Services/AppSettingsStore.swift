import Foundation

@MainActor
final class AppSettingsStore: ObservableObject {
    @Published var badgeStyle: MenuBarBadgeStyle {
        didSet {
            userDefaults.set(badgeStyle.rawValue, forKey: Keys.badgeStyle)
        }
    }

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

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        if let rawBadgeStyle = userDefaults.string(forKey: Keys.badgeStyle),
           let badgeStyle = MenuBarBadgeStyle(rawValue: rawBadgeStyle) {
            self.badgeStyle = badgeStyle
        } else {
            self.badgeStyle = .trailingCount
        }

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
        static let badgeStyle = "MenuBarBadgeStyle"
        static let quickAddShortcut = "QuickAddShortcut"
        static let trayShortcut = "TrayShortcut"
    }
}
