import Foundation
import XCTest
@testable import Tally

final class QuickAddWindowPositionStoreTests: XCTestCase {
    func testPersistsIndependentOffsetsForEachDisplay() {
        let userDefaults = makeUserDefaults()
        let store = QuickAddWindowPositionStore(userDefaults: userDefaults)

        store.setOffset(
            QuickAddWindowPositionOffset(x: 42, y: -18),
            for: "built-in-display"
        )
        store.setOffset(
            QuickAddWindowPositionOffset(x: -120, y: 64),
            for: "external-display"
        )

        let restoredStore = QuickAddWindowPositionStore(userDefaults: userDefaults)
        XCTAssertEqual(
            restoredStore.offset(for: "built-in-display"),
            QuickAddWindowPositionOffset(x: 42, y: -18)
        )
        XCTAssertEqual(
            restoredStore.offset(for: "external-display"),
            QuickAddWindowPositionOffset(x: -120, y: 64)
        )
    }

    func testRemovingAnOffsetDoesNotAffectOtherDisplays() {
        let userDefaults = makeUserDefaults()
        let store = QuickAddWindowPositionStore(userDefaults: userDefaults)
        store.setOffset(
            QuickAddWindowPositionOffset(x: 20, y: 30),
            for: "built-in-display"
        )
        store.setOffset(
            QuickAddWindowPositionOffset(x: 80, y: 90),
            for: "external-display"
        )

        store.removeOffset(for: "built-in-display")

        let restoredStore = QuickAddWindowPositionStore(userDefaults: userDefaults)
        XCTAssertNil(restoredStore.offset(for: "built-in-display"))
        XCTAssertEqual(
            restoredStore.offset(for: "external-display"),
            QuickAddWindowPositionOffset(x: 80, y: 90)
        )
    }

    func testIgnoresCorruptPersistence() {
        let userDefaults = makeUserDefaults()
        userDefaults.set(
            Data("not-json".utf8),
            forKey: "QuickAddWindowPositionOverrides"
        )

        let store = QuickAddWindowPositionStore(userDefaults: userDefaults)

        XCTAssertNil(store.offset(for: "built-in-display"))
    }

    func testRejectsNonFiniteOffsets() {
        let userDefaults = makeUserDefaults()
        let store = QuickAddWindowPositionStore(userDefaults: userDefaults)

        store.setOffset(
            QuickAddWindowPositionOffset(x: .nan, y: 20),
            for: "built-in-display"
        )

        XCTAssertNil(store.offset(for: "built-in-display"))
    }

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "TallyTests.QuickAddWindowPositionStore.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        return userDefaults
    }
}
