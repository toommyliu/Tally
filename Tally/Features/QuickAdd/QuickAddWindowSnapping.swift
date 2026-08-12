import AppKit

struct QuickAddSnapAxes: OptionSet, Equatable {
    let rawValue: Int

    static let horizontal = QuickAddSnapAxes(rawValue: 1 << 0)
    static let vertical = QuickAddSnapAxes(rawValue: 1 << 1)
    static let all: QuickAddSnapAxes = [.horizontal, .vertical]
}

struct QuickAddSnapResolution: Equatable {
    let origin: NSPoint
    let snappedAxes: QuickAddSnapAxes
}

enum QuickAddSnapAlignment {
    private static let tolerance: CGFloat = 0.5

    static func axes(
        origin: NSPoint,
        targetOrigin: NSPoint
    ) -> QuickAddSnapAxes {
        var axes: QuickAddSnapAxes = []
        if abs(origin.x - targetOrigin.x) <= tolerance {
            axes.insert(.horizontal)
        }
        if abs(origin.y - targetOrigin.y) <= tolerance {
            axes.insert(.vertical)
        }
        return axes
    }
}

struct QuickAddSnapFeedbackGate {
    private var wasSnappedToTarget = false

    mutating func shouldPerformFeedback(isSnappedToTarget: Bool) -> Bool {
        defer {
            wasSnappedToTarget = isSnappedToTarget
        }

        return isSnappedToTarget && !wasSnappedToTarget
    }

    mutating func reset() {
        wasSnappedToTarget = false
    }
}

struct QuickAddWindowHomeSnapResolver {
    let targetOrigin: NSPoint
    let engagementDistance: CGFloat
    let releaseDistance: CGFloat

    private var snappedAxes: QuickAddSnapAxes = []

    init(
        targetOrigin: NSPoint,
        engagementDistance: CGFloat,
        releaseDistance: CGFloat
    ) {
        precondition(engagementDistance >= 0)
        precondition(releaseDistance >= engagementDistance)

        self.targetOrigin = targetOrigin
        self.engagementDistance = engagementDistance
        self.releaseDistance = releaseDistance
    }

    mutating func resolve(
        proposedOrigin: NSPoint,
        eligibleAxes: QuickAddSnapAxes
    ) -> QuickAddSnapResolution {
        updateSnapState(
            axis: .horizontal,
            distance: abs(proposedOrigin.x - targetOrigin.x),
            eligibleAxes: eligibleAxes
        )
        updateSnapState(
            axis: .vertical,
            distance: abs(proposedOrigin.y - targetOrigin.y),
            eligibleAxes: eligibleAxes
        )

        return QuickAddSnapResolution(
            origin: NSPoint(
                x: snappedAxes.contains(.horizontal) ? targetOrigin.x : proposedOrigin.x,
                y: snappedAxes.contains(.vertical) ? targetOrigin.y : proposedOrigin.y
            ),
            snappedAxes: snappedAxes
        )
    }

    private mutating func updateSnapState(
        axis: QuickAddSnapAxes,
        distance: CGFloat,
        eligibleAxes: QuickAddSnapAxes
    ) {
        guard eligibleAxes.contains(axis) else {
            snappedAxes.remove(axis)
            return
        }

        let threshold = snappedAxes.contains(axis)
            ? releaseDistance
            : engagementDistance
        if distance <= threshold {
            snappedAxes.insert(axis)
        } else {
            snappedAxes.remove(axis)
        }
    }
}

enum QuickAddWindowSnapResolver {
    static let defaultThreshold: CGFloat = 9
    static let defaultEdgeInset: CGFloat = 10

    static func resolve(
        proposedOrigin: NSPoint,
        windowSize: NSSize,
        visibleFrame: NSRect,
        threshold: CGFloat = defaultThreshold,
        edgeInset: CGFloat = defaultEdgeInset,
        eligibleAxes: QuickAddSnapAxes = .all
    ) -> QuickAddSnapResolution {
        precondition(threshold >= 0)
        precondition(edgeInset >= 0)

        let horizontalAnchors = [
            visibleFrame.minX + edgeInset,
            visibleFrame.midX - windowSize.width / 2,
            visibleFrame.maxX - windowSize.width - edgeInset
        ]
        let verticalAnchors = [
            visibleFrame.minY + edgeInset,
            visibleFrame.midY - windowSize.height / 2,
            visibleFrame.maxY - windowSize.height - edgeInset
        ]

        let snappedX = eligibleAxes.contains(.horizontal)
            ? nearestAnchor(
                to: proposedOrigin.x,
                candidates: horizontalAnchors,
                threshold: threshold
            )
            : nil
        let snappedY = eligibleAxes.contains(.vertical)
            ? nearestAnchor(
                to: proposedOrigin.y,
                candidates: verticalAnchors,
                threshold: threshold
            )
            : nil

        var snappedAxes: QuickAddSnapAxes = []
        if snappedX != nil {
            snappedAxes.insert(.horizontal)
        }
        if snappedY != nil {
            snappedAxes.insert(.vertical)
        }

        let resolved = NSPoint(
            x: snappedX ?? proposedOrigin.x,
            y: snappedY ?? proposedOrigin.y
        )

        return QuickAddSnapResolution(
            origin: QuickAddWindowPlacement.clampedOrigin(
                resolved,
                windowSize: windowSize,
                visibleFrame: visibleFrame,
                edgeInset: edgeInset
            ),
            snappedAxes: snappedAxes
        )
    }

    private static func nearestAnchor(
        to value: CGFloat,
        candidates: [CGFloat],
        threshold: CGFloat
    ) -> CGFloat? {
        candidates
            .map { candidate in
                (value: candidate, distance: abs(candidate - value))
            }
            .filter { $0.distance <= threshold }
            .min { $0.distance < $1.distance }?
            .value
    }
}

struct QuickAddWindowDragSession {
    private let initialMouseLocation: NSPoint
    private let initialWindowOrigin: NSPoint
    private let targetOrigin: NSPoint
    private let releaseDistance: CGFloat
    private var eligibleAxes: QuickAddSnapAxes = []
    private var homeSnapResolver: QuickAddWindowHomeSnapResolver

    var eligibleSnapAxes: QuickAddSnapAxes {
        eligibleAxes
    }

    init(
        initialMouseLocation: NSPoint,
        initialWindowOrigin: NSPoint,
        targetOrigin: NSPoint,
        engagementDistance: CGFloat,
        releaseDistance: CGFloat
    ) {
        self.initialMouseLocation = initialMouseLocation
        self.initialWindowOrigin = initialWindowOrigin
        self.targetOrigin = targetOrigin
        self.releaseDistance = releaseDistance
        self.homeSnapResolver = QuickAddWindowHomeSnapResolver(
            targetOrigin: targetOrigin,
            engagementDistance: engagementDistance,
            releaseDistance: releaseDistance
        )

        if abs(initialWindowOrigin.x - targetOrigin.x) > releaseDistance {
            eligibleAxes.insert(.horizontal)
        }
        if abs(initialWindowOrigin.y - targetOrigin.y) > releaseDistance {
            eligibleAxes.insert(.vertical)
        }
    }

    func proposedOrigin(mouseLocation: NSPoint) -> NSPoint {
        NSPoint(
            x: initialWindowOrigin.x + mouseLocation.x - initialMouseLocation.x,
            y: initialWindowOrigin.y + mouseLocation.y - initialMouseLocation.y
        )
    }

    mutating func resolve(mouseLocation: NSPoint) -> QuickAddSnapResolution {
        let proposedOrigin = proposedOrigin(mouseLocation: mouseLocation)
        armAxesAfterLeavingTarget(proposedOrigin: proposedOrigin)
        return homeSnapResolver.resolve(
            proposedOrigin: proposedOrigin,
            eligibleAxes: eligibleAxes
        )
    }

    private mutating func armAxesAfterLeavingTarget(proposedOrigin: NSPoint) {
        if abs(proposedOrigin.x - targetOrigin.x) > releaseDistance {
            eligibleAxes.insert(.horizontal)
        }
        if abs(proposedOrigin.y - targetOrigin.y) > releaseDistance {
            eligibleAxes.insert(.vertical)
        }
    }
}

enum QuickAddDragHandleLayout {
    static let height: CGFloat = 14

    static func frame(
        panelSize: NSSize,
        cornerRadius: CGFloat
    ) -> NSRect {
        let horizontalInset = cornerRadius + 4
        return NSRect(
            x: horizontalInset,
            y: panelSize.height - height,
            width: max(0, panelSize.width - horizontalInset * 2),
            height: height
        )
    }
}

enum QuickAddWindowPlacement {
    static let edgeInset: CGFloat = 10

    static func defaultOrigin(
        windowSize: NSSize,
        visibleFrame: NSRect
    ) -> NSPoint {
        let topInset = min(max(visibleFrame.height * 0.10, 72), 104)
        return NSPoint(
            x: visibleFrame.midX - windowSize.width / 2,
            y: visibleFrame.maxY - topInset - windowSize.height
        )
    }

    /// Applies one display's saved displacement and keeps the panel fully visible.
    static func origin(
        applying offset: QuickAddWindowPositionOffset,
        to defaultOrigin: NSPoint,
        windowSize: NSSize,
        visibleFrame: NSRect
    ) -> NSPoint {
        clampedOrigin(
            NSPoint(
                x: defaultOrigin.x + offset.x,
                y: defaultOrigin.y + offset.y
            ),
            windowSize: windowSize,
            visibleFrame: visibleFrame,
            edgeInset: edgeInset
        )
    }

    /// Calculates the display-local override represented by a dragged origin.
    static func offset(
        from defaultOrigin: NSPoint,
        to origin: NSPoint
    ) -> QuickAddWindowPositionOffset {
        QuickAddWindowPositionOffset(
            x: origin.x - defaultOrigin.x,
            y: origin.y - defaultOrigin.y
        )
    }

    static func clampedOrigin(
        _ origin: NSPoint,
        windowSize: NSSize,
        visibleFrame: NSRect,
        edgeInset: CGFloat = edgeInset
    ) -> NSPoint {
        let minimumX = visibleFrame.minX + edgeInset
        let maximumX = max(minimumX, visibleFrame.maxX - windowSize.width - edgeInset)
        let minimumY = visibleFrame.minY + edgeInset
        let maximumY = max(minimumY, visibleFrame.maxY - windowSize.height - edgeInset)

        return NSPoint(
            x: min(max(origin.x, minimumX), maximumX),
            y: min(max(origin.y, minimumY), maximumY)
        )
    }
}
