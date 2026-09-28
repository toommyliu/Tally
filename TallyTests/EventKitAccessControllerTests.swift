import EventKit
import XCTest
@testable import Tally

@MainActor
final class EventKitAccessControllerTests: XCTestCase {
    func testAccessStatesExposeTheAppropriateUserAction() {
        XCTAssertEqual(EventKitAccessState.notDetermined.availableAction, .request)
        XCTAssertEqual(EventKitAccessState.requesting.availableAction, .none)
        XCTAssertEqual(EventKitAccessState.authorized.availableAction, .none)
        XCTAssertEqual(EventKitAccessState.denied.availableAction, .openSystemSettings)
    }

    func testWriteOnlyCalendarAccessIsTreatedAsDenied() {
        XCTAssertEqual(EventKitAccessController.state(for: .writeOnly), .denied)
    }

    func testInitialStateReflectsSystemPermissionWithoutPrompting() {
        var requestCount = 0
        let controller = EventKitAccessController(
            entity: .reminder,
            authorizationStatus: { .notDetermined },
            requestFullAccess: {
                requestCount += 1
                return true
            }
        )

        XCTAssertEqual(controller.state, .notDetermined)
        XCTAssertEqual(controller.refresh(), .notDetermined)
        XCTAssertEqual(requestCount, 0)
    }

    func testRefreshPublishesPermissionChangesMadeOutsideTally() {
        var status = EKAuthorizationStatus.denied
        let controller = EventKitAccessController(
            entity: .event,
            authorizationStatus: { status },
            requestFullAccess: { true }
        )

        status = .fullAccess

        XCTAssertEqual(controller.refresh(), .authorized)
        XCTAssertEqual(controller.state, .authorized)
    }

    func testRequestPromptsOnlyWhenPermissionIsUndetermined() async {
        var requestCount = 0
        let controller = EventKitAccessController(
            entity: .reminder,
            authorizationStatus: { .notDetermined },
            requestFullAccess: {
                requestCount += 1
                return true
            }
        )

        let state = await controller.requestIfNeeded()

        XCTAssertEqual(state, .authorized)
        XCTAssertEqual(controller.state, .authorized)
        XCTAssertEqual(requestCount, 1)
    }

    func testRequestDoesNotPromptWhenPermissionIsAlreadyGranted() async {
        var requestCount = 0
        let controller = EventKitAccessController(
            entity: .reminder,
            authorizationStatus: { .fullAccess },
            requestFullAccess: {
                requestCount += 1
                return false
            }
        )

        let state = await controller.requestIfNeeded()

        XCTAssertEqual(state, .authorized)
        XCTAssertEqual(requestCount, 0)
    }

    func testDeclinedPromptPublishesDenied() async {
        let controller = EventKitAccessController(
            entity: .event,
            authorizationStatus: { .notDetermined },
            requestFullAccess: { false }
        )

        let state = await controller.requestIfNeeded()

        XCTAssertEqual(state, .denied)
        XCTAssertEqual(controller.state, .denied)
    }

    func testConcurrentRequestsShareOnePromptAndStayRequestingUntilAnswered() async {
        var status = EKAuthorizationStatus.notDetermined
        var requestCount = 0
        var answerPrompt: CheckedContinuation<Bool, Never>?
        let controller = EventKitAccessController(
            entity: .event,
            authorizationStatus: { status },
            requestFullAccess: {
                requestCount += 1
                return await withCheckedContinuation { answerPrompt = $0 }
            }
        )

        let first = Task { await controller.requestIfNeeded() }
        let second = Task { await controller.requestIfNeeded() }

        while answerPrompt == nil {
            await Task.yield()
        }
        for _ in 0..<10 {
            await Task.yield()
        }

        XCTAssertEqual(controller.state, .requesting)
        XCTAssertEqual(controller.refresh(), .requesting)

        status = .fullAccess
        answerPrompt?.resume(returning: true)

        let firstState = await first.value
        let secondState = await second.value

        XCTAssertEqual(firstState, .authorized)
        XCTAssertEqual(secondState, .authorized)
        XCTAssertEqual(controller.state, .authorized)
        XCTAssertEqual(requestCount, 1)
    }

    func testDeniedActionOpensTheEntityPrivacyPane() async {
        var openedURLs: [URL] = []
        let controller = EventKitAccessController(
            entity: .event,
            authorizationStatus: { .denied },
            requestFullAccess: { true },
            openURL: { openedURLs.append($0) }
        )

        let action = await controller.performAvailableAction()

        XCTAssertEqual(action, .openSystemSettings)
        XCTAssertEqual(openedURLs, [EventKitEntity.event.privacySettingsURL])
    }

    func testUndeterminedActionRequestsAccess() async {
        var requestCount = 0
        let controller = EventKitAccessController(
            entity: .reminder,
            authorizationStatus: { .notDetermined },
            requestFullAccess: {
                requestCount += 1
                return true
            },
            openURL: { _ in XCTFail("Should not open System Settings") }
        )

        let action = await controller.performAvailableAction()

        XCTAssertEqual(action, .request)
        XCTAssertEqual(controller.state, .authorized)
        XCTAssertEqual(requestCount, 1)
    }
}
