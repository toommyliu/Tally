import EventKit
import Foundation

/// The kinds of EventKit data Tally works with. Each one has its own
/// permission, privacy settings pane, and owning Apple app.
enum EventKitEntity: CaseIterable {
    case reminder
    case event

    var entityType: EKEntityType {
        switch self {
        case .reminder:
            return .reminder
        case .event:
            return .event
        }
    }

    var appBundleIdentifier: String {
        switch self {
        case .reminder:
            return "com.apple.reminders"
        case .event:
            return "com.apple.iCal"
        }
    }

    var privacySettingsURL: URL {
        switch self {
        case .reminder:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")!
        case .event:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!
        }
    }
}
