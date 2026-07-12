import EventKit
import XCTest
@testable import Tally

@MainActor
final class ReminderAccessControllerTests: XCTestCase {
    func testAccessStatesExposeTheAppropriateUserAction() {
        XCTAssertEqual(ReminderAccessState.unknown.availableAction, .none)
        XCTAssertEqual(ReminderAccessState.notDetermined.availableAction, .request)
        XCTAssertEqual(ReminderAccessState.requesting.availableAction, .none)
        XCTAssertEqual(ReminderAccessState.authorized.availableAction, .none)
        XCTAssertEqual(ReminderAccessState.denied.availableAction, .openSystemSettings)
    }

    func testCurrentStateDoesNotRequestWhenPermissionIsUndetermined() {
        var requestCount = 0
        let controller = ReminderAccessController(
            authorizationStatus: { .notDetermined },
            requestFullAccess: {
                requestCount += 1
                return true
            }
        )

        XCTAssertEqual(controller.currentState(), .notDetermined)
        XCTAssertEqual(requestCount, 0)
    }

    func testRequestAccessPromptsOnlyWhenPermissionIsUndetermined() async {
        var requestCount = 0
        let controller = ReminderAccessController(
            authorizationStatus: { .notDetermined },
            requestFullAccess: {
                requestCount += 1
                return true
            }
        )

        let state = await controller.requestAccessIfNeeded()

        XCTAssertEqual(state, .authorized)
        XCTAssertEqual(requestCount, 1)
    }

    func testRequestAccessDoesNotPromptWhenPermissionIsAlreadyGranted() async {
        var requestCount = 0
        let controller = ReminderAccessController(
            authorizationStatus: { .fullAccess },
            requestFullAccess: {
                requestCount += 1
                return false
            }
        )

        let state = await controller.requestAccessIfNeeded()

        XCTAssertEqual(state, .authorized)
        XCTAssertEqual(requestCount, 0)
    }
}
