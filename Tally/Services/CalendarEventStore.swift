import Combine
import EventKit
import Foundation

/// Creates Apple Calendar events. Calendar access is requested only when the
/// user first switches Quick Add to Event mode, never at launch.
@MainActor
final class CalendarEventStore: ObservableObject {
    @Published private(set) var calendars: [CalendarDestinationInfo] = []
    @Published private(set) var accessState: EventKitAccessState
    @Published var errorMessage: String?

    let access: EventKitAccessController

    private let eventKit: EventKitService
    private let isUITesting: Bool
    private var changeSubscription: AnyCancellable?

    init(eventKit: EventKitService) {
        self.eventKit = eventKit
        access = eventKit.eventAccess
        accessState = eventKit.eventAccess.state
        isUITesting = eventKit.mode == .uiTesting
        access.$state
            .removeDuplicates()
            .assign(to: &$accessState)

        if isUITesting {
            calendars = [
                CalendarDestinationInfo(id: "ui-calendar-home", title: "Home", sourceTitle: "iCloud"),
                CalendarDestinationInfo(id: "ui-calendar-work", title: "Work", sourceTitle: "iCloud")
            ]
        }

        changeSubscription = eventKit.changes.sink { [weak self] in
            Task { @MainActor in
                self?.reloadCalendars()
            }
        }

        reloadCalendars()
    }

    var defaultCalendarTitle: String {
        if isUITesting {
            return calendars.first?.title ?? "Calendar"
        }

        guard access.state == .authorized else {
            return "Calendar"
        }

        return eventKit.defaultCalendar(for: .event)?.title ?? "Calendar"
    }

    /// Asks for Calendar access if the user hasn't decided yet, then loads the
    /// calendars Tally can write to.
    @discardableResult
    func prepareForEvents() async -> EventKitAccessState {
        let state = await access.requestIfNeeded()
        reloadCalendars()
        return state
    }

    @discardableResult
    func performAccessAction() async -> EventKitAccessAction {
        let action = await access.performAvailableAction()
        reloadCalendars()
        return action
    }

    func reloadCalendars() {
        guard !isUITesting else {
            return
        }

        guard access.refresh() == .authorized else {
            calendars = []
            return
        }

        calendars = eventKit
            .writableCalendars(for: .event)
            .map {
                CalendarDestinationInfo(
                    id: $0.calendarIdentifier,
                    title: $0.title,
                    sourceTitle: $0.source?.title
                )
            }
            .sorted(by: Self.isOrderedBefore)
    }

    func destinationTitle(for request: CalendarEventCreationRequest) -> String {
        if isUITesting {
            return uiTestingCalendar(for: request)?.title ?? defaultCalendarTitle
        }

        return eventKit.writableCalendar(for: .event, matching: request.destination)?.title
            ?? defaultCalendarTitle
    }

    @discardableResult
    func addEvent(_ request: CalendarEventCreationRequest) async -> Bool {
        guard !request.title.isEmpty else {
            return false
        }

        if isUITesting {
            return addUITestingEvent(request)
        }

        guard await access.requestIfNeeded() == .authorized else {
            errorMessage = access.state.eventSaveErrorMessage
            return false
        }

        do {
            guard let calendar = eventKit.writableCalendar(
                for: .event,
                matching: request.destination
            ) else {
                throw request.destination.isSpecific
                    ? CalendarEventStoreError.requestedCalendarUnavailable
                    : CalendarEventStoreError.noWritableCalendar
            }

            let event = EKEvent(eventStore: eventKit.eventStore)
            try CalendarEventEventKitMapper.populate(event, from: request, calendar: calendar)
            try eventKit.eventStore.save(event, span: .thisEvent, commit: true)
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func addUITestingEvent(_ request: CalendarEventCreationRequest) -> Bool {
        guard uiTestingCalendar(for: request) != nil else {
            errorMessage = request.destination.isSpecific
                ? CalendarEventStoreError.requestedCalendarUnavailable.localizedDescription
                : CalendarEventStoreError.noWritableCalendar.localizedDescription
            return false
        }

        errorMessage = nil
        return true
    }

    private func uiTestingCalendar(for request: CalendarEventCreationRequest) -> CalendarDestinationInfo? {
        CalendarDestinationResolver.resolve(
            request.destination,
            in: calendars,
            default: calendars.first,
            identifier: \.id,
            title: \.title
        )
    }

    private static func isOrderedBefore(_ lhs: CalendarDestinationInfo, _ rhs: CalendarDestinationInfo) -> Bool {
        let sourceOrder = (lhs.sourceTitle ?? "").localizedStandardCompare(rhs.sourceTitle ?? "")
        if sourceOrder != .orderedSame {
            return sourceOrder == .orderedAscending
        }

        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }
}

private enum CalendarEventStoreError: LocalizedError {
    case noWritableCalendar
    case requestedCalendarUnavailable

    var errorDescription: String? {
        switch self {
        case .noWritableCalendar:
            return "No writable calendar is available."
        case .requestedCalendarUnavailable:
            return "The requested calendar is unavailable or read-only."
        }
    }
}

extension EventKitAccessState {
    var eventSaveErrorMessage: String {
        switch self {
        case .notDetermined, .requesting:
            return "Waiting for Calendar access."
        case .denied:
            return "Tally needs full Calendar access. Turn it on in System Settings."
        case .authorized:
            return "The event could not be saved."
        }
    }
}
