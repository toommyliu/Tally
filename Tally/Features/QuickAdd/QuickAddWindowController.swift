import AppKit
import SwiftUI

@MainActor
final class QuickAddWindowController: NSObject, NSWindowDelegate {
    private static let windowSize = NSSize(
        width: TallyChrome.quickAddPanelSize.width,
        height: TallyChrome.quickAddPanelSize.height
    )
    private static let snapEngagementDistance: CGFloat = 12
    private static let snapReleaseDistance: CGFloat = 28
    private static let defaultVerticalCenterRatio: CGFloat = 0.72

    private let reminderStore: ReminderStore
    private var window: NSWindow?
    private var originalFrame: NSRect?
    private var snapGuideWindow: NSWindow?
    private var dragSession: QuickAddWindowDragSession?
    private var lastWindowOrigin: NSPoint?

    init(reminderStore: ReminderStore) {
        self.reminderStore = reminderStore
        super.init()
    }

    func show() {
        if window == nil {
            window = makeWindow()
        }

        guard let window else {
            return
        }

        position(window, size: Self.windowSize)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow,
              closingWindow === window else {
            return
        }

        lastWindowOrigin = closingWindow.frame.origin
        resetWindow()
    }

    func windowDidResignKey(_ notification: Notification) {
        guard window?.isVisible == true else {
            return
        }

        close()
    }

    private func resetWindow() {
        closeSnapGuide()
        window?.delegate = nil
        window?.contentViewController = nil
        window = nil
        originalFrame = nil
        dragSession = nil
    }

    private func makeWindow() -> NSWindow {
        let contentView = QuickAddWindowView(
            onCancel: { [weak self] in
                self?.close()
            },
            onSubmit: { [weak self] input, notes, shouldKeepOpen, suppressedInferredTokens in
                guard let self else {
                    return
                }

                Task {
                    await self.reminderStore.addReminder(
                        from: input,
                        notes: notes,
                        suppressedInferredTokens: suppressedInferredTokens
                    )
                    if shouldKeepOpen {
                        self.window?.makeKeyAndOrderFront(nil)
                    } else {
                        self.close()
                    }
                }
            }
        )
        .environmentObject(reminderStore)

        let panel = QuickAddPanel(
            contentRect: NSRect(origin: .zero, size: Self.windowSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        panel.contentViewController = makeContentViewController(rootView: contentView)
        panel.delegate = self
        panel.setContentSize(Self.windowSize)
        panel.contentMinSize = Self.windowSize
        panel.contentMaxSize = Self.windowSize
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.contentView?.prepareForTallyTransparentWindow()

        return panel
    }

    private func position(_ window: NSWindow, size: NSSize) {
        let restoredFrame = lastWindowOrigin.map { NSRect(origin: $0, size: size) }
        let screen = restoredFrame.flatMap(screenBestMatching) ?? screenContainingMouse() ?? NSScreen.main

        guard let visibleFrame = screen?.visibleFrame else {
            window.setFrame(NSRect(origin: .zero, size: size), display: false)
            window.center()
            originalFrame = window.frame

            if let lastWindowOrigin {
                window.setFrame(NSRect(origin: lastWindowOrigin, size: size), display: false)
            }
            return
        }

        let defaultOrigin = NSPoint(
            x: visibleFrame.midX - size.width / 2,
            y: defaultOriginY(for: size, in: visibleFrame)
        )
        originalFrame = NSRect(origin: defaultOrigin, size: size)

        let origin = lastWindowOrigin.flatMap { rememberedOrigin in
            QuickAddWindowPlacement.restoredOrigin(
                rememberedOrigin,
                windowSize: size,
                visibleFrame: visibleFrame
            )
        } ?? defaultOrigin
        window.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    private func defaultOriginY(for size: NSSize, in visibleFrame: NSRect) -> CGFloat {
        let targetCenterY = visibleFrame.minY + visibleFrame.height * Self.defaultVerticalCenterRatio
        let unclampedOriginY = targetCenterY - size.height / 2
        let maxOriginY = max(visibleFrame.minY, visibleFrame.maxY - size.height)
        return min(max(unclampedOriginY, visibleFrame.minY), maxOriginY)
    }

    private func makeContentViewController<Content: View>(rootView: Content) -> NSViewController {
        let containerController = NSViewController()
        let containerView = NSView(frame: NSRect(origin: .zero, size: Self.windowSize))
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.clear.cgColor
        containerController.view = containerView

        let hostingController = NSHostingController.tallyClearBackground(rootView: rootView)
        containerController.addChild(hostingController)
        hostingController.view.frame = containerView.bounds
        hostingController.view.autoresizingMask = [.width, .height]
        containerView.addSubview(hostingController.view)

        let dragHandle = QuickAddDragHandleView()
        dragHandle.onDragBegan = { [weak self] mouseLocation in
            self?.beginWindowDrag(at: mouseLocation)
        }
        dragHandle.onDragChanged = { [weak self] mouseLocation in
            self?.updateWindowDrag(to: mouseLocation)
        }
        dragHandle.onDragEnded = { [weak self] in
            self?.finishWindowDrag()
        }
        dragHandle.frame = QuickAddDragHandleLayout.frame(
            panelSize: Self.windowSize,
            shadowPadding: TallyChrome.quickAddShadowPadding,
            cornerRadius: TallyChrome.panelCornerRadius
        )
        containerView.addSubview(dragHandle)

        return containerController
    }

    private func beginWindowDrag(at mouseLocation: NSPoint) {
        guard let window,
              let originalFrame else {
            return
        }

        dragSession = QuickAddWindowDragSession(
            initialMouseLocation: mouseLocation,
            initialWindowOrigin: window.frame.origin,
            targetOrigin: originalFrame.origin,
            engagementDistance: Self.snapEngagementDistance,
            releaseDistance: Self.snapReleaseDistance
        )
        updateSnapGuide(
            snappedAxes: QuickAddSnapAlignment.axes(
                origin: window.frame.origin,
                targetOrigin: originalFrame.origin
            ),
            originalFrame: originalFrame,
            relativeTo: window
        )
    }

    private func updateWindowDrag(to mouseLocation: NSPoint) {
        guard let window,
              let originalFrame,
              var dragSession else {
            return
        }

        let resolution = dragSession.resolve(mouseLocation: mouseLocation)
        self.dragSession = dragSession

        if resolution.origin != window.frame.origin {
            window.setFrameOrigin(resolution.origin)
        }

        updateSnapGuide(snappedAxes: resolution.snappedAxes, originalFrame: originalFrame, relativeTo: window)
    }

    private func finishWindowDrag() {
        guard dragSession != nil else {
            return
        }

        lastWindowOrigin = window?.frame.origin
        dragSession = nil
        hideSnapGuide()
    }

    private func updateSnapGuide(
        snappedAxes: QuickAddSnapAxes,
        originalFrame: NSRect,
        relativeTo window: NSWindow
    ) {
        let guideFrame = snapGuideFrame(for: originalFrame)
        let guideWindow = snapGuideWindow ?? makeSnapGuideWindow(frame: guideFrame)
        snapGuideWindow = guideWindow

        if guideWindow.frame != guideFrame {
            guideWindow.setFrame(guideFrame, display: true)
        }

        if let guideView = guideWindow.contentView as? QuickAddSnapGuideView {
            guideView.snappedAxes = snappedAxes
        }

        guideWindow.order(.above, relativeTo: window.windowNumber)
    }

    private func snapGuideFrame(for originalFrame: NSRect) -> NSRect {
        originalFrame
    }

    private func makeSnapGuideWindow(frame: NSRect) -> NSWindow {
        let guideWindow = QuickAddSnapGuidePanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        guideWindow.contentView = QuickAddSnapGuideView(
            frame: NSRect(origin: .zero, size: frame.size)
        )
        guideWindow.isReleasedWhenClosed = false
        guideWindow.ignoresMouseEvents = true
        guideWindow.hidesOnDeactivate = false
        guideWindow.level = .floating
        guideWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        guideWindow.backgroundColor = .clear
        guideWindow.isOpaque = false
        guideWindow.hasShadow = false

        return guideWindow
    }

    private func hideSnapGuide() {
        snapGuideWindow?.orderOut(nil)
    }

    private func closeSnapGuide() {
        snapGuideWindow?.close()
        snapGuideWindow = nil
    }

    private func screenContainingMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { screen in
            screen.frame.contains(mouseLocation)
        }
    }

    private func screenBestMatching(_ frame: NSRect) -> NSScreen? {
        NSScreen.screens.max { lhs, rhs in
            lhs.visibleFrame.intersection(frame).area < rhs.visibleFrame.intersection(frame).area
        }.flatMap { screen in
            screen.visibleFrame.intersects(frame) ? screen : nil
        }
    }
}

private extension NSRect {
    var area: CGFloat {
        guard !isNull, !isEmpty else {
            return 0
        }

        return width * height
    }
}

private final class QuickAddPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }
}

private final class QuickAddDragHandleView: NSView {
    private static let minimumDragDistance: CGFloat = 3

    var onDragBegan: ((NSPoint) -> Void)?
    var onDragChanged: ((NSPoint) -> Void)?
    var onDragEnded: (() -> Void)?

    private var mouseDownLocation: NSPoint?
    private var isDragging = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = NSEvent.mouseLocation
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let mouseDownLocation else {
            return
        }

        let currentLocation = NSEvent.mouseLocation
        if !isDragging {
            let xDelta = currentLocation.x - mouseDownLocation.x
            let yDelta = currentLocation.y - mouseDownLocation.y
            guard hypot(xDelta, yDelta) >= Self.minimumDragDistance else {
                return
            }

            isDragging = true
            NSCursor.closedHand.push()
            onDragBegan?(mouseDownLocation)
        }

        onDragChanged?(currentLocation)
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            mouseDownLocation = nil
        }

        guard isDragging else {
            return
        }

        isDragging = false
        NSCursor.pop()
        onDragEnded?()
    }
}

private final class QuickAddSnapGuidePanel: NSPanel {
    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }
}

private final class QuickAddSnapGuideView: NSView {
    var snappedAxes: QuickAddSnapAxes = [] {
        didSet {
            needsDisplay = true
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var isOpaque: Bool {
        false
    }

    override func draw(_ dirtyRect: NSRect) {
        let surfacePadding = TallyChrome.quickAddShadowPadding
        let surfaceRect = bounds.insetBy(dx: surfacePadding, dy: surfacePadding)
        let targetPath = NSBezierPath(
            roundedRect: surfaceRect,
            xRadius: TallyChrome.panelCornerRadius,
            yRadius: TallyChrome.panelCornerRadius
        )
        let dashPattern: [CGFloat] = [6, 6]
        targetPath.setLineDash(dashPattern, count: dashPattern.count, phase: 0)
        targetPath.lineWidth = 1.5
        NSColor.secondaryLabelColor.withAlphaComponent(0.42).setStroke()
        targetPath.stroke()

        drawSnappedAxes(around: surfaceRect, dashPattern: dashPattern)
    }

    private func drawSnappedAxes(around surfaceRect: NSRect, dashPattern: [CGFloat]) {
        guard !snappedAxes.isEmpty else {
            return
        }

        let path: NSBezierPath
        if snappedAxes == .all {
            path = NSBezierPath(
                roundedRect: surfaceRect,
                xRadius: TallyChrome.panelCornerRadius,
                yRadius: TallyChrome.panelCornerRadius
            )
        } else {
            path = NSBezierPath()
            let cornerInset = TallyChrome.panelCornerRadius

            if snappedAxes.contains(.horizontal) {
                path.move(to: NSPoint(x: surfaceRect.minX, y: surfaceRect.minY + cornerInset))
                path.line(to: NSPoint(x: surfaceRect.minX, y: surfaceRect.maxY - cornerInset))
                path.move(to: NSPoint(x: surfaceRect.maxX, y: surfaceRect.minY + cornerInset))
                path.line(to: NSPoint(x: surfaceRect.maxX, y: surfaceRect.maxY - cornerInset))
            }

            if snappedAxes.contains(.vertical) {
                path.move(to: NSPoint(x: surfaceRect.minX + cornerInset, y: surfaceRect.minY))
                path.line(to: NSPoint(x: surfaceRect.maxX - cornerInset, y: surfaceRect.minY))
                path.move(to: NSPoint(x: surfaceRect.minX + cornerInset, y: surfaceRect.maxY))
                path.line(to: NSPoint(x: surfaceRect.maxX - cornerInset, y: surfaceRect.maxY))
            }
        }

        path.setLineDash(dashPattern, count: dashPattern.count, phase: 0)
        path.lineWidth = 2
        NSColor.controlAccentColor.withAlphaComponent(0.9).setStroke()
        path.stroke()
    }
}
