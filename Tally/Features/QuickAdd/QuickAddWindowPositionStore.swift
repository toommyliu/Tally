import AppKit
import CoreGraphics
import Foundation

/// A user-chosen displacement from Quick Add's default origin on one display.
struct QuickAddWindowPositionOffset: Codable, Equatable {
    let x: CGFloat
    let y: CGFloat

    var isFinite: Bool {
        x.isFinite && y.isFinite
    }
}

/// Resolves a stable identifier for associating window state with a physical display.
enum QuickAddDisplayIdentity {
    static func identifier(for screen: NSScreen) -> String? {
        let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")
        guard let screenNumber = screen.deviceDescription[screenNumberKey] as? NSNumber,
              let displayUUID = CGDisplayCreateUUIDFromDisplayID(
                  CGDirectDisplayID(screenNumber.uint32Value)
              )?.takeRetainedValue()
        else {
            return nil
        }

        return CFUUIDCreateString(nil, displayUUID) as String
    }
}

/// Persists independent Quick Add position overrides for each display.
final class QuickAddWindowPositionStore {
    private static let storageKey = "QuickAddWindowPositionOverrides"

    private let userDefaults: UserDefaults
    private var offsetsByDisplayIdentifier: [String: QuickAddWindowPositionOffset]

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.offsetsByDisplayIdentifier = Self.loadOffsets(from: userDefaults)
    }

    /// Returns the custom offset for a display, or `nil` when it should use the default origin.
    func offset(for displayIdentifier: String) -> QuickAddWindowPositionOffset? {
        offsetsByDisplayIdentifier[displayIdentifier]
    }

    /// Saves a finite custom offset for one display without affecting other displays.
    func setOffset(
        _ offset: QuickAddWindowPositionOffset,
        for displayIdentifier: String
    ) {
        guard !displayIdentifier.isEmpty, offset.isFinite else {
            return
        }

        guard offsetsByDisplayIdentifier[displayIdentifier] != offset else {
            return
        }

        offsetsByDisplayIdentifier[displayIdentifier] = offset
        persistOffsets()
    }

    /// Removes one display's override so future presentations use its default origin.
    func removeOffset(for displayIdentifier: String) {
        guard offsetsByDisplayIdentifier.removeValue(forKey: displayIdentifier) != nil else {
            return
        }

        persistOffsets()
    }

    private static func loadOffsets(
        from userDefaults: UserDefaults
    ) -> [String: QuickAddWindowPositionOffset] {
        guard let data = userDefaults.data(forKey: storageKey),
              let offsets = try? JSONDecoder().decode(
                  [String: QuickAddWindowPositionOffset].self,
                  from: data
              )
        else {
            return [:]
        }

        return offsets.filter { identifier, offset in
            !identifier.isEmpty && offset.isFinite
        }
    }

    private func persistOffsets() {
        guard let data = try? JSONEncoder().encode(offsetsByDisplayIdentifier) else {
            return
        }

        userDefaults.set(data, forKey: Self.storageKey)
    }
}
