import AppKit
import XCTest
@testable import Tally

final class QuickAddWindowSnappingTests: XCTestCase {
    func testSnapAlignmentReflectsActualAxesAtTarget() {
        let targetOrigin = NSPoint(x: 100, y: 200)

        XCTAssertEqual(
            QuickAddSnapAlignment.axes(origin: targetOrigin, targetOrigin: targetOrigin),
            .all
        )
        XCTAssertEqual(
            QuickAddSnapAlignment.axes(origin: NSPoint(x: 100, y: 250), targetOrigin: targetOrigin),
            .horizontal
        )
        XCTAssertEqual(
            QuickAddSnapAlignment.axes(origin: NSPoint(x: 150, y: 200), targetOrigin: targetOrigin),
            .vertical
        )
        XCTAssertEqual(
            QuickAddSnapAlignment.axes(origin: NSPoint(x: 150, y: 250), targetOrigin: targetOrigin),
            []
        )
    }

    func testRestoresRememberedWindowOriginWhenItRemainsVisible() {
        let rememberedOrigin = NSPoint(x: 300, y: 500)

        let restoredOrigin = QuickAddWindowPlacement.restoredOrigin(
            rememberedOrigin,
            windowSize: NSSize(width: 596, height: 244),
            visibleFrame: NSRect(x: 0, y: 0, width: 1512, height: 949)
        )

        XCTAssertEqual(restoredOrigin, rememberedOrigin)
    }

    func testRejectsRememberedWindowOriginThatIsNoLongerUsablyVisible() {
        let restoredOrigin = QuickAddWindowPlacement.restoredOrigin(
            NSPoint(x: 1480, y: 930),
            windowSize: NSSize(width: 596, height: 244),
            visibleFrame: NSRect(x: 0, y: 0, width: 1512, height: 949)
        )

        XCTAssertNil(restoredOrigin)
    }

    func testDragHandleOccupiesTopPaddingInsideVisibleSurface() {
        let frame = QuickAddDragHandleLayout.frame(
            panelSize: NSSize(width: 596, height: 244),
            shadowPadding: 28,
            cornerRadius: 20
        )

        XCTAssertEqual(frame, NSRect(x: 48, y: 198, width: 500, height: 18))
        XCTAssertEqual(frame.maxY, 244 - 28)
        XCTAssertGreaterThan(frame.minY, 0)
    }

    func testDragFollowsMouseExactlyBeforeSnapIsArmed() {
        var session = makeDragSession()

        let resolution = session.resolve(mouseLocation: NSPoint(x: 412, y: 391))

        XCTAssertEqual(resolution.origin, NSPoint(x: 112, y: 191))
        XCTAssertEqual(resolution.snappedAxes, [])
    }

    func testDragCanLeaveTargetWithoutInitialStickiness() {
        var session = makeDragSession()

        let firstMovement = session.resolve(mouseLocation: NSPoint(x: 405, y: 400))
        let secondMovement = session.resolve(mouseLocation: NSPoint(x: 415, y: 400))

        XCTAssertEqual(firstMovement.origin.x, 105)
        XCTAssertEqual(secondMovement.origin.x, 115)
    }

    func testDragSnapsLiveAfterLeavingAndReturningToTarget() {
        var session = makeDragSession()
        _ = session.resolve(mouseLocation: NSPoint(x: 440, y: 440))

        let resolution = session.resolve(mouseLocation: NSPoint(x: 409, y: 391))

        XCTAssertEqual(resolution.origin, NSPoint(x: 100, y: 200))
        XCTAssertEqual(resolution.snappedAxes, .all)
    }

    func testDragKeepsLockedAxisUntilCursorCrossesReleaseDistance() {
        var session = makeDragSession()
        _ = session.resolve(mouseLocation: NSPoint(x: 440, y: 400))
        _ = session.resolve(mouseLocation: NSPoint(x: 408, y: 400))

        let retained = session.resolve(mouseLocation: NSPoint(x: 426, y: 400))
        let released = session.resolve(mouseLocation: NSPoint(x: 429, y: 400))

        XCTAssertEqual(retained.origin.x, 100)
        XCTAssertEqual(released.origin.x, 129)
    }

    func testDragPositionAlwaysUsesMouseDownOriginInsteadOfAccumulatingSnapCorrections() {
        var session = makeDragSession()
        _ = session.resolve(mouseLocation: NSPoint(x: 440, y: 400))
        _ = session.resolve(mouseLocation: NSPoint(x: 408, y: 400))

        let released = session.resolve(mouseLocation: NSPoint(x: 440, y: 400))

        XCTAssertEqual(released.origin.x, 140)
    }

    func testSnapsEachAxisIndependently() {
        var resolver = makeResolver()

        let horizontal = resolver.resolve(proposedOrigin: NSPoint(x: 108, y: 250))
        XCTAssertEqual(horizontal.origin, NSPoint(x: 100, y: 250))
        XCTAssertEqual(horizontal.snappedAxes, .horizontal)

        let vertical = resolver.resolve(proposedOrigin: NSPoint(x: 200, y: 207))
        XCTAssertEqual(vertical.origin, NSPoint(x: 200, y: 200))
        XCTAssertEqual(vertical.snappedAxes, .vertical)
    }

    func testSnapsBothAxesInsideEngagementDistance() {
        var resolver = makeResolver()

        let resolution = resolver.resolve(proposedOrigin: NSPoint(x: 92, y: 209))

        XCTAssertEqual(resolution.origin, NSPoint(x: 100, y: 200))
        XCTAssertEqual(resolution.snappedAxes, .all)
    }

    func testHysteresisKeepsAxisSnappedUntilReleaseDistanceIsExceeded() {
        var resolver = makeResolver()
        _ = resolver.resolve(proposedOrigin: NSPoint(x: 100, y: 300))

        let retained = resolver.resolve(proposedOrigin: NSPoint(x: 124, y: 300))
        XCTAssertEqual(retained.origin.x, 100)
        XCTAssertTrue(retained.snappedAxes.contains(.horizontal))

        let released = resolver.resolve(proposedOrigin: NSPoint(x: 127, y: 300))
        XCTAssertEqual(released.origin.x, 127)
        XCTAssertFalse(released.snappedAxes.contains(.horizontal))
    }

    func testReleasedAxisDoesNotReengageOutsideEngagementDistance() {
        var resolver = makeResolver()
        _ = resolver.resolve(proposedOrigin: NSPoint(x: 100, y: 300))
        _ = resolver.resolve(proposedOrigin: NSPoint(x: 140, y: 300))

        let outsideMagneticZone = resolver.resolve(proposedOrigin: NSPoint(x: 115, y: 300))
        XCTAssertEqual(outsideMagneticZone.origin.x, 115)
        XCTAssertFalse(outsideMagneticZone.snappedAxes.contains(.horizontal))

        let reengaged = resolver.resolve(proposedOrigin: NSPoint(x: 110, y: 300))
        XCTAssertEqual(reengaged.origin.x, 100)
        XCTAssertTrue(reengaged.snappedAxes.contains(.horizontal))
    }

    private func makeResolver() -> QuickAddSnapResolver {
        QuickAddSnapResolver(
            targetOrigin: NSPoint(x: 100, y: 200),
            engagementDistance: 10,
            releaseDistance: 26
        )
    }

    private func makeDragSession() -> QuickAddWindowDragSession {
        QuickAddWindowDragSession(
            initialMouseLocation: NSPoint(x: 400, y: 400),
            initialWindowOrigin: NSPoint(x: 100, y: 200),
            targetOrigin: NSPoint(x: 100, y: 200),
            engagementDistance: 10,
            releaseDistance: 28
        )
    }
}
