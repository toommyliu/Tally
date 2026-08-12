import AppKit
import XCTest
@testable import Tally

final class QuickAddWindowSnappingTests: XCTestCase {
    private let windowSize = NSSize(width: 590, height: 190)
    private let visibleFrame = NSRect(x: 0, y: 0, width: 1512, height: 949)

    func testDefaultOriginIsCenteredNearTheTopOfTheVisibleScreen() {
        let origin = QuickAddWindowPlacement.defaultOrigin(
            windowSize: windowSize,
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(origin.x, 461, accuracy: 0.001)
        XCTAssertEqual(origin.y, 664.1, accuracy: 0.001)
        XCTAssertEqual(origin.x + windowSize.width / 2, visibleFrame.midX, accuracy: 0.001)
    }

    func testAppliesSavedOffsetToTargetDisplayDefault() {
        let origin = QuickAddWindowPlacement.origin(
            applying: QuickAddWindowPositionOffset(x: -100, y: 40),
            to: NSPoint(x: 400, y: 500),
            windowSize: windowSize,
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(origin, NSPoint(x: 300, y: 540))
    }

    func testSavedOffsetIsClampedFullyInsideTheTargetDisplay() {
        let origin = QuickAddWindowPlacement.origin(
            applying: QuickAddWindowPositionOffset(x: -1_000, y: 1_000),
            to: NSPoint(x: 400, y: 500),
            windowSize: windowSize,
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(origin, NSPoint(x: 10, y: 749))
    }

    func testCalculatesOffsetFromTargetDisplayDefault() {
        let offset = QuickAddWindowPlacement.offset(
            from: NSPoint(x: 400, y: 500),
            to: NSPoint(x: 300, y: 540)
        )

        XCTAssertEqual(offset, QuickAddWindowPositionOffset(x: -100, y: 40))
    }

    func testDragHandleOnlyOccupiesTheTopPadding() {
        let frame = QuickAddDragHandleLayout.frame(
            panelSize: windowSize,
            cornerRadius: 14
        )

        XCTAssertEqual(frame, NSRect(x: 18, y: 176, width: 554, height: 14))
    }

    func testAlignmentReportsAxesAtTheStartingPosition() {
        let targetOrigin = NSPoint(x: 100, y: 200)

        XCTAssertEqual(
            QuickAddSnapAlignment.axes(
                origin: targetOrigin,
                targetOrigin: targetOrigin
            ),
            .all
        )
        XCTAssertEqual(
            QuickAddSnapAlignment.axes(
                origin: NSPoint(x: 100, y: 250),
                targetOrigin: targetOrigin
            ),
            .horizontal
        )
        XCTAssertEqual(
            QuickAddSnapAlignment.axes(
                origin: NSPoint(x: 150, y: 200),
                targetOrigin: targetOrigin
            ),
            .vertical
        )
    }

    func testFeedbackFiresOncePerSnapTransition() {
        var gate = QuickAddSnapFeedbackGate()

        XCTAssertFalse(gate.shouldPerformFeedback(isSnappedToTarget: false))
        XCTAssertTrue(gate.shouldPerformFeedback(isSnappedToTarget: true))
        XCTAssertFalse(gate.shouldPerformFeedback(isSnappedToTarget: true))
        XCTAssertFalse(gate.shouldPerformFeedback(isSnappedToTarget: false))
        XCTAssertTrue(gate.shouldPerformFeedback(isSnappedToTarget: true))

        gate.reset()

        XCTAssertTrue(gate.shouldPerformFeedback(isSnappedToTarget: true))
    }

    func testDragSessionAlwaysUsesTheMouseDownOrigin() {
        var session = makeDragSession()

        XCTAssertEqual(
            session.proposedOrigin(mouseLocation: NSPoint(x: 412, y: 391)),
            NSPoint(x: 112, y: 191)
        )
        XCTAssertEqual(
            session.proposedOrigin(mouseLocation: NSPoint(x: 440, y: 430)),
            NSPoint(x: 140, y: 230)
        )

        _ = session.resolve(mouseLocation: NSPoint(x: 440, y: 430))
        _ = session.resolve(mouseLocation: NSPoint(x: 409, y: 409))

        XCTAssertEqual(
            session.resolve(mouseLocation: NSPoint(x: 440, y: 430)).origin,
            NSPoint(x: 140, y: 230)
        )
    }

    func testDragLeavesTheStartingPositionWithoutInitialStickiness() {
        var session = makeDragSession()

        let firstMovement = session.resolve(mouseLocation: NSPoint(x: 405, y: 400))
        let secondMovement = session.resolve(mouseLocation: NSPoint(x: 415, y: 400))

        XCTAssertEqual(firstMovement.origin, NSPoint(x: 105, y: 200))
        XCTAssertEqual(secondMovement.origin, NSPoint(x: 115, y: 200))
        XCTAssertEqual(firstMovement.snappedAxes, [])
        XCTAssertEqual(secondMovement.snappedAxes, [])
        XCTAssertEqual(session.eligibleSnapAxes, [])

        _ = session.resolve(mouseLocation: NSPoint(x: 429, y: 400))

        XCTAssertEqual(session.eligibleSnapAxes, .horizontal)
    }

    func testDragSnapsLiveWhenReturningToTheStartingPosition() {
        var session = makeDragSession()
        _ = session.resolve(mouseLocation: NSPoint(x: 440, y: 440))

        let resolution = session.resolve(mouseLocation: NSPoint(x: 409, y: 391))

        XCTAssertEqual(resolution.origin, NSPoint(x: 100, y: 200))
        XCTAssertEqual(resolution.snappedAxes, .all)
    }

    func testHomeSnapHysteresisPreventsChatterNearTheCaptureBoundary() {
        var session = makeDragSession()
        _ = session.resolve(mouseLocation: NSPoint(x: 440, y: 400))
        _ = session.resolve(mouseLocation: NSPoint(x: 408, y: 400))

        let retained = session.resolve(mouseLocation: NSPoint(x: 426, y: 400))
        let released = session.resolve(mouseLocation: NSPoint(x: 429, y: 400))
        let remainsFree = session.resolve(mouseLocation: NSPoint(x: 415, y: 400))
        let recaptured = session.resolve(mouseLocation: NSPoint(x: 412, y: 400))

        XCTAssertEqual(retained.origin.x, 100)
        XCTAssertTrue(retained.snappedAxes.contains(.horizontal))
        XCTAssertEqual(released.origin.x, 129)
        XCTAssertFalse(released.snappedAxes.contains(.horizontal))
        XCTAssertEqual(remainsFree.origin.x, 115)
        XCTAssertFalse(remainsFree.snappedAxes.contains(.horizontal))
        XCTAssertEqual(recaptured.origin.x, 100)
        XCTAssertTrue(recaptured.snappedAxes.contains(.horizontal))
    }

    func testHomeSnapTreatsEachAxisIndependently() {
        var session = QuickAddWindowDragSession(
            initialMouseLocation: NSPoint(x: 400, y: 400),
            initialWindowOrigin: NSPoint(x: 180, y: 280),
            targetOrigin: NSPoint(x: 100, y: 200),
            engagementDistance: 12,
            releaseDistance: 28
        )

        let horizontal = session.resolve(mouseLocation: NSPoint(x: 322, y: 400))
        let vertical = session.resolve(mouseLocation: NSPoint(x: 400, y: 322))

        XCTAssertEqual(horizontal.origin, NSPoint(x: 100, y: 280))
        XCTAssertEqual(horizontal.snappedAxes, .horizontal)
        XCTAssertEqual(vertical.origin, NSPoint(x: 180, y: 200))
        XCTAssertEqual(vertical.snappedAxes, .vertical)
    }

    func testSnapsToScreenCenterOnBothAxes() {
        let resolution = QuickAddWindowSnapResolver.resolve(
            proposedOrigin: NSPoint(x: 460, y: 375),
            windowSize: windowSize,
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(resolution.origin.x, 461, accuracy: 0.001)
        XCTAssertEqual(resolution.origin.y, 379.5, accuracy: 0.001)
        XCTAssertEqual(resolution.snappedAxes, .all)
    }

    func testSnapsToInsetScreenEdges() {
        let resolution = QuickAddWindowSnapResolver.resolve(
            proposedOrigin: NSPoint(x: 16, y: 744),
            windowSize: windowSize,
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(resolution.origin, NSPoint(x: 10, y: 749))
        XCTAssertEqual(resolution.snappedAxes, .all)
    }

    func testSnapsEachAxisIndependently() {
        let resolution = QuickAddWindowSnapResolver.resolve(
            proposedOrigin: NSPoint(x: 460, y: 220),
            windowSize: windowSize,
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(resolution.origin, NSPoint(x: 461, y: 220))
        XCTAssertEqual(resolution.snappedAxes, .horizontal)
    }

    func testFreeDragDoesNotSnapOutsideTheSmallMagneticZone() {
        let resolution = QuickAddWindowSnapResolver.resolve(
            proposedOrigin: NSPoint(x: 100, y: 100),
            windowSize: windowSize,
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(resolution.origin, NSPoint(x: 100, y: 100))
        XCTAssertEqual(resolution.snappedAxes, [])
    }

    func testScreenSnapWaitsUntilTheDragHasLeftItsStartingAxis() {
        let resolution = QuickAddWindowSnapResolver.resolve(
            proposedOrigin: NSPoint(x: 466, y: 384),
            windowSize: windowSize,
            visibleFrame: visibleFrame,
            eligibleAxes: []
        )

        XCTAssertEqual(resolution.origin, NSPoint(x: 466, y: 384))
        XCTAssertEqual(resolution.snappedAxes, [])
    }

    func testDragCannotLoseTheWindowBeyondAVisibleScreenEdge() {
        let resolution = QuickAddWindowSnapResolver.resolve(
            proposedOrigin: NSPoint(x: -80, y: 1200),
            windowSize: windowSize,
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(resolution.origin, NSPoint(x: 10, y: 749))
    }

    private func makeDragSession() -> QuickAddWindowDragSession {
        QuickAddWindowDragSession(
            initialMouseLocation: NSPoint(x: 400, y: 400),
            initialWindowOrigin: NSPoint(x: 100, y: 200),
            targetOrigin: NSPoint(x: 100, y: 200),
            engagementDistance: 12,
            releaseDistance: 28
        )
    }
}
