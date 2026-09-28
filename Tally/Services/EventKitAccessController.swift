import AppKit
import EventKit
import Foundation

enum EventKitAccessState: Equatable {
    case notDetermined
    case requesting
    case authorized
    case denied
}

enum EventKitAccessAction: Equatable {
    case request
    case openSystemSettings
    case none
}

extension EventKitAccessState {
    var availableAction: EventKitAccessAction {
        switch self {
        case .notDetermined:
            return .request
        case .denied:
            return .openSystemSettings
        case .requesting, .authorized:
            return .none
        }
    }
}

/// Tracks and requests full access for one EventKit entity type.
@MainActor
final class EventKitAccessController: ObservableObject {
    let entity: EventKitEntity

    @Published private(set) var state: EventKitAccessState

    private let authorizationStatus: () -> EKAuthorizationStatus
    private let requestFullAccess: @MainActor () async -> Bool
    private let openURL: (URL) -> Void
    private var activeRequest: Task<EventKitAccessState, Never>?

    convenience init(entity: EventKitEntity, eventStore: EKEventStore) {
        self.init(
            entity: entity,
            authorizationStatus: {
                EKEventStore.authorizationStatus(for: entity.entityType)
            },
            requestFullAccess: {
                await Self.requestFullAccess(to: entity, in: eventStore)
            }
        )
    }

    init(
        entity: EventKitEntity,
        authorizationStatus: @escaping () -> EKAuthorizationStatus,
        requestFullAccess: @escaping @MainActor () async -> Bool,
        openURL: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) }
    ) {
        self.entity = entity
        self.authorizationStatus = authorizationStatus
        self.requestFullAccess = requestFullAccess
        self.openURL = openURL
        state = Self.state(for: authorizationStatus())
    }

    /// Re-reads the system permission without prompting. While a prompt is on
    /// screen the state stays `.requesting` until the user answers.
    @discardableResult
    func refresh() -> EventKitAccessState {
        guard activeRequest == nil else {
            return state
        }

        let currentState = Self.state(for: authorizationStatus())
        if state != currentState {
            state = currentState
        }
        return currentState
    }

    /// Prompts only when the user hasn't decided yet. Concurrent callers share
    /// a single system prompt.
    @discardableResult
    func requestIfNeeded() async -> EventKitAccessState {
        if let activeRequest {
            return await awaitRequest(activeRequest)
        }

        let currentState = refresh()
        guard currentState == .notDetermined else {
            return currentState
        }

        let request = Task { @MainActor [requestFullAccess] () -> EventKitAccessState in
            await requestFullAccess() ? .authorized : .denied
        }
        activeRequest = request
        state = .requesting
        return await awaitRequest(request)
    }

    @discardableResult
    func performAvailableAction() async -> EventKitAccessAction {
        let action = refresh().availableAction

        switch action {
        case .request:
            await requestIfNeeded()
        case .openSystemSettings:
            openPrivacySettings()
        case .none:
            break
        }

        return action
    }

    func openPrivacySettings() {
        openURL(entity.privacySettingsURL)
    }

    static func state(for status: EKAuthorizationStatus) -> EventKitAccessState {
        switch status {
        case .fullAccess, .authorized:
            return .authorized
        case .notDetermined:
            return .notDetermined
        case .denied, .restricted, .writeOnly:
            return .denied
        @unknown default:
            return .denied
        }
    }

    private func awaitRequest(_ request: Task<EventKitAccessState, Never>) async -> EventKitAccessState {
        let result = await request.value

        if activeRequest == request {
            activeRequest = nil
            state = result
        }

        return result
    }

    private static func requestFullAccess(
        to entity: EventKitEntity,
        in eventStore: EKEventStore
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            switch entity {
            case .reminder:
                eventStore.requestFullAccessToReminders { granted, _ in
                    continuation.resume(returning: granted)
                }
            case .event:
                eventStore.requestFullAccessToEvents { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        }
    }
}

extension EventKitAccessController {
    /// An access controller that reports full access without touching the
    /// system permission, for deterministic UI tests.
    static func alwaysAuthorized(entity: EventKitEntity) -> EventKitAccessController {
        EventKitAccessController(
            entity: entity,
            authorizationStatus: { .fullAccess },
            requestFullAccess: { true },
            openURL: { _ in }
        )
    }
}
