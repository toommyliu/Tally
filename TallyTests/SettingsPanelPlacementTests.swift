import AppKit
import XCTest
@testable import Tally

final class SettingsPanelPlacementTests: XCTestCase {
    func testAnchoredPanelCentersBelowStatusItem() {
        let frame = SettingsPanelPlacement.frame(
            anchorRect: NSRect(x: 490, y: 970, width: 20, height: 22),
            panelSize: NSSize(width: 420, height: 620),
            visibleFrame: NSRect(x: 0, y: 0, width: 1_000, height: 1_000)
        )

        XCTAssertEqual(frame.origin.x, 290)
        XCTAssertEqual(frame.origin.y, 344)
    }

    func testAnchoredPanelStaysInsideVisibleScreenEdges() {
        let frame = SettingsPanelPlacement.frame(
            anchorRect: NSRect(x: 8, y: 970, width: 20, height: 22),
            panelSize: NSSize(width: 420, height: 620),
            visibleFrame: NSRect(x: 0, y: 0, width: 1_000, height: 1_000)
        )

        XCTAssertEqual(frame.minX, 8)
        XCTAssertGreaterThanOrEqual(frame.minY, 8)
        XCTAssertLessThanOrEqual(frame.maxX, 992)
        XCTAssertLessThanOrEqual(frame.maxY, 992)
    }

    func testReducedMotionTransitionDoesNotMovePanel() {
        let frame = NSRect(x: 100, y: 200, width: 420, height: 620)

        XCTAssertEqual(
            SettingsPanelTransition.presentedStartFrame(from: frame, reduceMotion: true),
            frame
        )
        XCTAssertEqual(
            SettingsPanelTransition.dismissedFrame(from: frame, reduceMotion: true),
            frame
        )
    }
}
