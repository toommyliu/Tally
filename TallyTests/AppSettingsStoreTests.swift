import Carbon.HIToolbox
import Foundation
import XCTest
@testable import Tally

@MainActor
final class AppSettingsStoreTests: XCTestCase {
    func testUsesDefaultQuickAddShortcutWhenUnset() {
        let userDefaults = makeUserDefaults()
        let store = AppSettingsStore(userDefaults: userDefaults)

        XCTAssertEqual(store.quickAddShortcut, .defaultQuickAddValue)
    }

    func testPreservesInvalidStoredQuickAddShortcut() throws {
        let userDefaults = makeUserDefaults()
        let invalidShortcut = GlobalShortcut.invalidValue
        let encodedShortcut = try JSONEncoder().encode(invalidShortcut)
        userDefaults.set(encodedShortcut, forKey: "QuickAddShortcut")

        let store = AppSettingsStore(userDefaults: userDefaults)

        XCTAssertEqual(store.quickAddShortcut, invalidShortcut)
        XCTAssertEqual(store.quickAddShortcut.displayTitle, "Invalid")
    }

    func testCorruptStoredQuickAddShortcutDisplaysAsInvalid() {
        let userDefaults = makeUserDefaults()
        userDefaults.set(Data("not-json".utf8), forKey: "QuickAddShortcut")

        let store = AppSettingsStore(userDefaults: userDefaults)

        XCTAssertEqual(store.quickAddShortcut, .invalidValue)
        XCTAssertEqual(store.quickAddShortcut.displayTitle, "Invalid")
    }

    func testPreservesStoredTrayShortcut() throws {
        let userDefaults = makeUserDefaults()
        let storedShortcut = GlobalShortcut(
            keyEquivalent: "t",
            keyCode: UInt16(kVK_ANSI_T),
            modifiers: [.control, .option, .command]
        )
        let encodedShortcut = try JSONEncoder().encode(storedShortcut)
        userDefaults.set(encodedShortcut, forKey: "TrayShortcut")

        let store = AppSettingsStore(userDefaults: userDefaults)

        XCTAssertEqual(store.trayShortcut, storedShortcut)
    }

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "TallyTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        return userDefaults
    }
}
