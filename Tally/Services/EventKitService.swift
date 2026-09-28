import AppKit
import Combine
import EventKit

/// Owns Tally's single `EKEventStore` and the pieces reminder and calendar
/// features share: permissions, change notifications, and calendar lookup.
@MainActor
final class EventKitService {
    enum Mode: Equatable {
        case live
        /// Reports full access without touching the user's data so UI tests
        /// run deterministically.
        case uiTesting

        static var current: Mode {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
                return .uiTesting
            }
            #endif

            return .live
        }
    }

    let mode: Mode
    let eventStore: EKEventStore
    let reminderAccess: EventKitAccessController
    let eventAccess: EventKitAccessController

    init(mode: Mode = .current, eventStore: EKEventStore = EKEventStore()) {
        self.mode = mode
        self.eventStore = eventStore

        switch mode {
        case .live:
            reminderAccess = EventKitAccessController(entity: .reminder, eventStore: eventStore)
            eventAccess = EventKitAccessController(entity: .event, eventStore: eventStore)
        case .uiTesting:
            reminderAccess = .alwaysAuthorized(entity: .reminder)
            eventAccess = .alwaysAuthorized(entity: .event)
        }
    }

    /// Emits on the main queue whenever Calendar, Reminders, iCloud, or
    /// another app changes the store, so cached state can be refetched.
    var changes: AnyPublisher<Void, Never> {
        NotificationCenter.default
            .publisher(for: .EKEventStoreChanged, object: eventStore)
            .map { _ in () }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    func writableCalendars(for entity: EventKitEntity) -> [EKCalendar] {
        eventStore
            .calendars(for: entity.entityType)
            .filter(\.allowsContentModifications)
    }

    func defaultCalendar(for entity: EventKitEntity) -> EKCalendar? {
        switch entity {
        case .reminder:
            return eventStore.defaultCalendarForNewReminders()
        case .event:
            return eventStore.defaultCalendarForNewEvents
        }
    }

    func writableCalendar(
        for entity: EventKitEntity,
        matching query: CalendarDestinationQuery
    ) -> EKCalendar? {
        let defaultCalendar = defaultCalendar(for: entity)
            .flatMap { $0.allowsContentModifications ? $0 : nil }

        return CalendarDestinationResolver.resolve(
            query,
            in: writableCalendars(for: entity),
            default: defaultCalendar,
            identifier: \.calendarIdentifier,
            title: \.title
        )
    }

    func openApp(for entity: EventKitEntity) {
        guard let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: entity.appBundleIdentifier
        ) else {
            return
        }

        NSWorkspace.shared.openApplication(
            at: url,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }
}
