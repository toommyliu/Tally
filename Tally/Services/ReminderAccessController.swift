import EventKit
import Foundation

enum ReminderAccessState: Equatable {
    case unknown
    case notDetermined
    case requesting
    case authorized
    case denied
}

enum ReminderAccessAction: Equatable {
    case request
    case openSystemSettings
    case none
}

extension ReminderAccessState {
    var availableAction: ReminderAccessAction {
        switch self {
        case .notDetermined:
            return .request
        case .denied:
            return .openSystemSettings
        case .unknown, .requesting, .authorized:
            return .none
        }
    }
}

@MainActor
final class ReminderAccessController {
    private let authorizationStatus: () -> EKAuthorizationStatus
    private let requestFullAccess: () async -> Bool
    private var activeRequest: Task<Bool, Never>?

    convenience init(eventStore: EKEventStore) {
        self.init(
            authorizationStatus: {
                EKEventStore.authorizationStatus(for: .reminder)
            },
            requestFullAccess: {
                await withCheckedContinuation { continuation in
                    eventStore.requestFullAccessToReminders { granted, _ in
                        continuation.resume(returning: granted)
                    }
                }
            }
        )
    }

    init(
        authorizationStatus: @escaping () -> EKAuthorizationStatus,
        requestFullAccess: @escaping () async -> Bool
    ) {
        self.authorizationStatus = authorizationStatus
        self.requestFullAccess = requestFullAccess
    }

    func currentState() -> ReminderAccessState {
        Self.state(for: authorizationStatus())
    }

    func requestAccessIfNeeded() async -> ReminderAccessState {
        switch authorizationStatus() {
        case .fullAccess, .authorized:
            return .authorized
        case .notDetermined:
            let granted = await requestUserAccess()
            return granted ? .authorized : .denied
        case .denied, .restricted, .writeOnly:
            return .denied
        @unknown default:
            return .denied
        }
    }

    static func state(for status: EKAuthorizationStatus) -> ReminderAccessState {
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

    private func requestUserAccess() async -> Bool {
        if let activeRequest {
            return await activeRequest.value
        }

        let request = Task { await requestFullAccess() }
        activeRequest = request
        let granted = await request.value
        activeRequest = nil
        return granted
    }
}
