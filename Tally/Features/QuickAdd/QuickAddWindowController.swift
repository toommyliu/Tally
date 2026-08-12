import AppKit
import SwiftUI

@MainActor
final class QuickAddWindowController: NSObject, NSWindowDelegate {
    private static let windowSize = NSSize(
        width: TallyChrome.quickAddPanelSize.width,
        height: TallyChrome.quickAddPanelSize.height
    )
    private static let maximumWindowHeight: CGFloat = 270
    private static let snapEngagementDistance: CGFloat = 12
    private static let snapReleaseDistance: CGFloat = 28

    private let reminderStore: ReminderStore
    private let settingsStore: AppSettingsStore
    private let positionStore: QuickAddWindowPositionStore
    private var window: NSWindow?
    private var draft: QuickAddDraft?
    private var dragSession: QuickAddWindowDragSession?
    private var snapFeedbackGate = QuickAddSnapFeedbackGate()
    private var snapGuideWindow: NSWindow?
    private var startingWindowOrigin: NSPoint?
    private var escapeKeyMonitor: Any?

    init(reminderStore: ReminderStore, settingsStore: AppSettingsStore) {
        self.reminderStore = reminderStore
        self.settingsStore = settingsStore
        self.positionStore = settingsStore.quickAddWindowPositionStore
        super.init()
    }

    func show(on targetScreen: NSScreen?) {
        if window == nil {
            window = makeWindow()
        }

        guard let window else {
            return
        }

        position(window, size: window.frame.size, on: targetScreen)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKey()
        DispatchQueue.main.async { [weak window] in
            guard window?.isVisible == true else {
                return
            }

            NSApp.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil)
        }
    }

    private func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow,
              closingWindow === window else {
            return
        }

        resetWindow()
    }

    func windowDidResignKey(_ notification: Notification) {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard !arguments.contains("--ui-testing"),
              !arguments.contains("--keep-quick-add-open-on-resign") else {
            return
        }
        #endif

        guard window?.isVisible == true else {
            return
        }

        close()
    }

    private func resetWindow() {
        closeSnapGuide()

        if let escapeKeyMonitor {
            NSEvent.removeMonitor(escapeKeyMonitor)
            self.escapeKeyMonitor = nil
        }

        window?.delegate = nil
        window?.contentViewController = nil
        window = nil
        draft = nil
        dragSession = nil
        snapFeedbackGate.reset()
        startingWindowOrigin = nil
    }

    private func makeWindow() -> NSWindow {
        let draft = QuickAddDraft(settingsStore: settingsStore)
        self.draft = draft
        let contentView = QuickAddWindowView(
            draft: draft,
            onCancel: { [weak self] in
                self?.close()
            },
            onSubmit: { [weak self] request in
                self?.submit(request)
            },
            onPreferredHeightChange: { [weak self] height in
                self?.resizeWindow(toPreferredHeight: height)
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
        panel.title = "Quick Add"
        panel.delegate = self
        panel.onRequestClose = { [weak self] in
            self?.close()
        }
        panel.setContentSize(Self.windowSize)
        panel.contentMinSize = Self.windowSize
        panel.contentMaxSize = NSSize(
            width: Self.windowSize.width,
            height: Self.maximumWindowHeight
        )
        panel.isMovableByWindowBackground = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentView?.prepareForTallyTransparentWindow()
        installEscapeKeyMonitor(for: panel)

        return panel
    }

    private func installEscapeKeyMonitor(for panel: QuickAddPanel) {
        if let escapeKeyMonitor {
            NSEvent.removeMonitor(escapeKeyMonitor)
        }

        escapeKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self, weak panel] event in
            guard let self,
                  let panel,
                  panel.isVisible,
                  QuickAddPanel.isPlainEscape(event)
            else {
                return event
            }

            // A SwiftUI popover owns a separate panel and should dismiss one level
            // through its own onExitCommand handler.
            if let eventWindow = event.window,
               eventWindow !== panel,
               eventWindow is NSPanel {
                return event
            }

            if QuickAddEscapeRouting.defersToFirstResponder(panel.firstResponder) {
                return event
            }

            close()
            return nil
        }
    }

    private func submit(_ request: ReminderCreationRequest) {
        guard let draft else {
            return
        }

        let keepsOpenAfterAdd = draft.keepsOpenAfterAdd
        let destinationListTitle = reminderStore.destinationListTitle(for: request)

        Task { @MainActor [weak self, weak draft] in
            guard let self else {
                return
            }

            let didSave = await reminderStore.addReminder(request)
            guard let draft, draft === self.draft else {
                return
            }

            if didSave {
                draft.didSave(to: destinationListTitle)
                if keepsOpenAfterAdd {
                    window?.makeKeyAndOrderFront(nil)
                } else {
                    close()
                }
            } else {
                draft.reportSaveFailure(
                    reminderStore.errorMessage ?? "The reminder could not be saved."
                )
                window?.makeKeyAndOrderFront(nil)
            }
        }
    }

    private func position(
        _ window: NSWindow,
        size: NSSize,
        on targetScreen: NSScreen?
    ) {
        let screen = targetScreen
            ?? screenContainingMouse()
            ?? NSScreen.main

        guard let screen else {
            window.setFrame(NSRect(origin: .zero, size: size), display: false)
            window.center()
            startingWindowOrigin = window.frame.origin
            return
        }

        let visibleFrame = screen.visibleFrame

        let defaultOrigin = QuickAddWindowPlacement.defaultOrigin(
            windowSize: size,
            visibleFrame: visibleFrame
        )
        startingWindowOrigin = defaultOrigin

        let origin = QuickAddDisplayIdentity.identifier(for: screen)
            .flatMap { positionStore.offset(for: $0) }
            .map { offset in
                QuickAddWindowPlacement.origin(
                    applying: offset,
                    to: defaultOrigin,
                    windowSize: size,
                    visibleFrame: visibleFrame
                )
            } ?? defaultOrigin

        window.setFrame(NSRect(origin: origin, size: size), display: true)
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
            cornerRadius: TallyChrome.panelCornerRadius
        )
        dragHandle.autoresizingMask = [.width, .minYMargin]
        containerView.addSubview(dragHandle)

        return containerController
    }

    private func beginWindowDrag(at mouseLocation: NSPoint) {
        guard let window,
              let startingWindowOrigin else {
            return
        }

        dragSession = QuickAddWindowDragSession(
            initialMouseLocation: mouseLocation,
            initialWindowOrigin: window.frame.origin,
            targetOrigin: startingWindowOrigin,
            engagementDistance: Self.snapEngagementDistance,
            releaseDistance: Self.snapReleaseDistance
        )
        snapFeedbackGate.reset()
        updateSnapGuide(
            alignedAxes: QuickAddSnapAlignment.axes(
                origin: window.frame.origin,
                targetOrigin: startingWindowOrigin
            ),
            targetFrame: NSRect(
                origin: startingWindowOrigin,
                size: window.frame.size
            ),
            relativeTo: window
        )
    }

    private func updateWindowDrag(to mouseLocation: NSPoint) {
        guard let window,
              var dragSession else {
            return
        }

        let homeResolution = dragSession.resolve(mouseLocation: mouseLocation)
        self.dragSession = dragSession

        let windowSize = window.frame.size
        let proposedFrame = NSRect(origin: homeResolution.origin, size: windowSize)
        let screen = screenBestMatching(proposedFrame) ?? window.screen ?? screenContainingMouse()

        let resolvedOrigin: NSPoint
        if let visibleFrame = screen?.visibleFrame {
            resolvedOrigin = QuickAddWindowSnapResolver.resolve(
                proposedOrigin: homeResolution.origin,
                windowSize: windowSize,
                visibleFrame: visibleFrame,
                eligibleAxes: dragSession.eligibleSnapAxes
            ).origin
        } else {
            resolvedOrigin = homeResolution.origin
        }

        if resolvedOrigin != window.frame.origin {
            window.setFrameOrigin(resolvedOrigin)
        }

        guard let startingWindowOrigin else {
            return
        }

        let alignedAxes = QuickAddSnapAlignment.axes(
            origin: resolvedOrigin,
            targetOrigin: startingWindowOrigin
        )
        updateSnapGuide(
            alignedAxes: alignedAxes,
            targetFrame: NSRect(
                origin: startingWindowOrigin,
                size: windowSize
            ),
            relativeTo: window
        )

        let didMagneticallySnapToTarget =
            alignedAxes == .all &&
            !homeResolution.snappedAxes.isEmpty
        if snapFeedbackGate.shouldPerformFeedback(
            isSnappedToTarget: didMagneticallySnapToTarget
        ) {
            NSHapticFeedbackManager.defaultPerformer.perform(
                .generic,
                performanceTime: .now
            )
        }
    }

    private func finishWindowDrag() {
        guard dragSession != nil else {
            return
        }

        persistWindowPositionAfterDrag()
        dragSession = nil
        snapFeedbackGate.reset()
        hideSnapGuide()
    }

    /// Persists a custom offset on the display where an explicit drag ended.
    private func persistWindowPositionAfterDrag() {
        guard let window,
              let screen = window.screen ?? screenBestMatching(window.frame)
        else {
            return
        }

        let defaultOrigin = QuickAddWindowPlacement.defaultOrigin(
            windowSize: window.frame.size,
            visibleFrame: screen.visibleFrame
        )
        startingWindowOrigin = defaultOrigin

        guard let displayIdentifier = QuickAddDisplayIdentity.identifier(
            for: screen
        ) else {
            return
        }

        let alignedAxes = QuickAddSnapAlignment.axes(
            origin: window.frame.origin,
            targetOrigin: defaultOrigin
        )
        if alignedAxes == .all {
            positionStore.removeOffset(for: displayIdentifier)
            return
        }

        positionStore.setOffset(
            QuickAddWindowPlacement.offset(
                from: defaultOrigin,
                to: window.frame.origin
            ),
            for: displayIdentifier
        )
    }

    private func updateSnapGuide(
        alignedAxes: QuickAddSnapAxes,
        targetFrame: NSRect,
        relativeTo window: NSWindow
    ) {
        let guideWindow = snapGuideWindow ?? makeSnapGuideWindow(frame: targetFrame)
        snapGuideWindow = guideWindow

        if guideWindow.frame != targetFrame {
            guideWindow.setFrame(targetFrame, display: true)
        }

        if let guideView = guideWindow.contentView as? QuickAddSnapGuideView {
            guideView.alignedAxes = alignedAxes
        }

        if alignedAxes == .all {
            guideWindow.orderOut(nil)
        } else if !guideWindow.isVisible {
            guideWindow.order(.below, relativeTo: window.windowNumber)
        }
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
        guideWindow.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .transient,
            .ignoresCycle
        ]
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

    private func resizeWindow(toPreferredHeight preferredHeight: CGFloat) {
        guard let window else {
            return
        }

        let height = min(
            max(preferredHeight, Self.windowSize.height),
            Self.maximumWindowHeight
        )
        guard abs(window.frame.height - height) > 0.5 else {
            return
        }

        let oldFrame = window.frame
        let size = NSSize(width: Self.windowSize.width, height: height)
        var origin = NSPoint(x: oldFrame.minX, y: oldFrame.maxY - height)
        if var startingWindowOrigin {
            startingWindowOrigin.y -= height - oldFrame.height
            self.startingWindowOrigin = startingWindowOrigin
        }

        if let visibleFrame = window.screen?.visibleFrame {
            origin = QuickAddWindowPlacement.clampedOrigin(
                origin,
                windowSize: size,
                visibleFrame: visibleFrame,
                edgeInset: QuickAddWindowPlacement.edgeInset
            )
        }

        window.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    private func screenContainingMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { screen in
            screen.frame.contains(mouseLocation)
        }
    }

    private func screenBestMatching(_ frame: NSRect) -> NSScreen? {
        let screen = NSScreen.screens.max { lhs, rhs in
            lhs.visibleFrame.intersection(frame).area < rhs.visibleFrame.intersection(frame).area
        }

        guard let screen,
              screen.visibleFrame.intersection(frame).area > 0 else {
            return nil
        }

        return screen
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

enum QuickAddEscapeRouting {
    /// Text editors receive Escape first so they can dismiss token recognition.
    static func defersToFirstResponder(_ firstResponder: NSResponder?) -> Bool {
        firstResponder is NSTextView
    }
}

private final class QuickAddPanel: NSPanel {
    private static let escapeKeyCode: UInt16 = 53

    var onRequestClose: (() -> Void)?

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    override func sendEvent(_ event: NSEvent) {
        if Self.isPlainEscape(event),
           !QuickAddEscapeRouting.defersToFirstResponder(firstResponder) {
            requestClose()
            return
        }

        super.sendEvent(event)
    }

    override func cancelOperation(_ sender: Any?) {
        requestClose()
    }

    private func requestClose() {
        onRequestClose?() ?? close()
    }

    fileprivate static func isPlainEscape(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              event.keyCode == escapeKeyCode
        else {
            return false
        }

        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        return flags.isEmpty
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
    var alignedAxes: QuickAddSnapAxes = [] {
        didSet {
            guard alignedAxes != oldValue else {
                return
            }

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
        drawTargetOutline()
        drawRulers()
    }

    private func drawTargetOutline() {
        let path = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 0.75, dy: 0.75),
            xRadius: TallyChrome.panelCornerRadius,
            yRadius: TallyChrome.panelCornerRadius
        )
        let dashPattern: [CGFloat] = [6, 5]
        path.setLineDash(dashPattern, count: dashPattern.count, phase: 0)
        path.lineWidth = alignedAxes == .all ? 2 : 1.5

        let color = alignedAxes == .all
            ? NSColor.controlAccentColor.withAlphaComponent(0.88)
            : NSColor.secondaryLabelColor.withAlphaComponent(0.44)
        color.setStroke()
        path.stroke()
    }

    private func drawRulers() {
        drawRuler(
            from: NSPoint(x: bounds.midX, y: bounds.minY),
            to: NSPoint(x: bounds.midX, y: bounds.maxY),
            isAligned: alignedAxes.contains(.horizontal)
        )
        drawRuler(
            from: NSPoint(x: bounds.minX, y: bounds.midY),
            to: NSPoint(x: bounds.maxX, y: bounds.midY),
            isAligned: alignedAxes.contains(.vertical)
        )
    }

    private func drawRuler(
        from start: NSPoint,
        to end: NSPoint,
        isAligned: Bool
    ) {
        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: end)

        let dashPattern: [CGFloat] = isAligned ? [7, 4] : [3, 5]
        path.setLineDash(dashPattern, count: dashPattern.count, phase: 0)
        path.lineWidth = isAligned ? 1.5 : 1

        let color = isAligned
            ? NSColor.controlAccentColor.withAlphaComponent(0.72)
            : NSColor.secondaryLabelColor.withAlphaComponent(0.25)
        color.setStroke()
        path.stroke()
    }
}
