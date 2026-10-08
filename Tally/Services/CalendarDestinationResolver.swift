import Foundation

/// A writable reminder list or event calendar that new items can be saved to.
struct CalendarDestinationInfo: Identifiable, Equatable, Hashable {
    let id: String
    let title: String
    /// The account that owns the destination, such as iCloud or Gmail.
    var sourceTitle: String? = nil
}

/// Identifies the reminder list or calendar a new item should be saved to.
/// An explicit identifier wins over a name; with neither, the default is used.
struct CalendarDestinationQuery: Equatable {
    let identifier: String?
    let name: String?

    var isSpecific: Bool {
        identifier != nil || name != nil
    }
}

enum CalendarDestinationResolver {
    /// Returns `nil` when a specific destination was requested but isn't
    /// writable, so callers never silently save somewhere else.
    static func resolve<Destination>(
        _ query: CalendarDestinationQuery,
        in writableDestinations: [Destination],
        default defaultDestination: Destination?,
        identifier: (Destination) -> String,
        title: (Destination) -> String
    ) -> Destination? {
        if let requestedIdentifier = query.identifier {
            return writableDestinations.first {
                identifier($0) == requestedIdentifier
            }
        }

        if let requestedName = query.name {
            return writableDestinations.first {
                title($0).compare(
                    requestedName,
                    options: [.caseInsensitive, .diacriticInsensitive]
                ) == .orderedSame
            }
        }

        return defaultDestination ?? writableDestinations.first
    }
}
