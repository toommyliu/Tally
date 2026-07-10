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

    static func axes(origin: NSPoint, targetOrigin: NSPoint) -> QuickAddSnapAxes {
        var alignedAxes: QuickAddSnapAxes = []
        if abs(origin.x - targetOrigin.x) <= tolerance {
            alignedAxes.insert(.horizontal)
        }
        if abs(origin.y - targetOrigin.y) <= tolerance {
            alignedAxes.insert(.vertical)
        }
        return alignedAxes
    }
}

struct QuickAddSnapResolver {
    let targetOrigin: NSPoint
    let engagementDistance: CGFloat
    let releaseDistance: CGFloat

    private var isHorizontallySnapped = false
    private var isVerticallySnapped = false

    init(targetOrigin: NSPoint, engagementDistance: CGFloat, releaseDistance: CGFloat) {
        precondition(engagementDistance >= 0)
        precondition(releaseDistance >= engagementDistance)

        self.targetOrigin = targetOrigin
        self.engagementDistance = engagementDistance
        self.releaseDistance = releaseDistance
    }

    mutating func resolve(
        proposedOrigin: NSPoint,
        eligibleAxes: QuickAddSnapAxes = .all
    ) -> QuickAddSnapResolution {
        isHorizontallySnapped = eligibleAxes.contains(.horizontal) && Self.shouldSnap(
            proposedValue: proposedOrigin.x,
            targetValue: targetOrigin.x,
            isCurrentlySnapped: isHorizontallySnapped,
            engagementDistance: engagementDistance,
            releaseDistance: releaseDistance
        )
        isVerticallySnapped = eligibleAxes.contains(.vertical) && Self.shouldSnap(
            proposedValue: proposedOrigin.y,
            targetValue: targetOrigin.y,
            isCurrentlySnapped: isVerticallySnapped,
            engagementDistance: engagementDistance,
            releaseDistance: releaseDistance
        )

        var snappedAxes: QuickAddSnapAxes = []
        if isHorizontallySnapped {
            snappedAxes.insert(.horizontal)
        }
        if isVerticallySnapped {
            snappedAxes.insert(.vertical)
        }

        return QuickAddSnapResolution(
            origin: NSPoint(
                x: isHorizontallySnapped ? targetOrigin.x : proposedOrigin.x,
                y: isVerticallySnapped ? targetOrigin.y : proposedOrigin.y
            ),
            snappedAxes: snappedAxes
        )
    }

    private static func shouldSnap(
        proposedValue: CGFloat,
        targetValue: CGFloat,
        isCurrentlySnapped: Bool,
        engagementDistance: CGFloat,
        releaseDistance: CGFloat
    ) -> Bool {
        let threshold = isCurrentlySnapped ? releaseDistance : engagementDistance
        return abs(proposedValue - targetValue) <= threshold
    }
}

struct QuickAddWindowDragSession {
    private let initialMouseLocation: NSPoint
    private let initialWindowOrigin: NSPoint
    private let targetOrigin: NSPoint
    private let releaseDistance: CGFloat
    private var eligibleAxes: QuickAddSnapAxes = []
    private var snapResolver: QuickAddSnapResolver

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
        self.snapResolver = QuickAddSnapResolver(
            targetOrigin: targetOrigin,
            engagementDistance: engagementDistance,
            releaseDistance: releaseDistance
        )
    }

    mutating func resolve(mouseLocation: NSPoint) -> QuickAddSnapResolution {
        let proposedOrigin = NSPoint(
            x: initialWindowOrigin.x + mouseLocation.x - initialMouseLocation.x,
            y: initialWindowOrigin.y + mouseLocation.y - initialMouseLocation.y
        )
        armAxesDepartingFromTarget(proposedOrigin: proposedOrigin)

        let resolution = snapResolver.resolve(
            proposedOrigin: proposedOrigin,
            eligibleAxes: eligibleAxes
        )
        return QuickAddSnapResolution(
            origin: resolution.origin,
            snappedAxes: resolution.snappedAxes.union(QuickAddSnapAlignment.axes(
                origin: resolution.origin,
                targetOrigin: targetOrigin
            ))
        )
    }

    private mutating func armAxesDepartingFromTarget(proposedOrigin: NSPoint) {
        if abs(proposedOrigin.x - targetOrigin.x) > releaseDistance {
            eligibleAxes.insert(.horizontal)
        }
        if abs(proposedOrigin.y - targetOrigin.y) > releaseDistance {
            eligibleAxes.insert(.vertical)
        }
    }
}

enum QuickAddDragHandleLayout {
    static let height: CGFloat = 18

    static func frame(
        panelSize: NSSize,
        shadowPadding: CGFloat,
        cornerRadius: CGFloat
    ) -> NSRect {
        let horizontalInset = shadowPadding + cornerRadius
        return NSRect(
            x: horizontalInset,
            y: panelSize.height - shadowPadding - height,
            width: max(0, panelSize.width - horizontalInset * 2),
            height: height
        )
    }
}

enum QuickAddWindowPlacement {
    private static let minimumVisibleSize = NSSize(width: 96, height: 44)

    static func restoredOrigin(
        _ rememberedOrigin: NSPoint,
        windowSize: NSSize,
        visibleFrame: NSRect
    ) -> NSPoint? {
        let rememberedFrame = NSRect(origin: rememberedOrigin, size: windowSize)
        let visibleIntersection = rememberedFrame.intersection(visibleFrame)
        guard !visibleIntersection.isNull,
              visibleIntersection.width >= min(minimumVisibleSize.width, windowSize.width),
              visibleIntersection.height >= min(minimumVisibleSize.height, windowSize.height) else {
            return nil
        }

        return rememberedOrigin
    }
}
