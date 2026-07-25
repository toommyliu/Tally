import AppKit
import SwiftUI

final class SettingsPanel: NSPanel {
    var onRequestClose: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if Self.isCloseShortcut(event) {
            requestClose()
            return true
        }

        if Self.isSelectAllShortcut(event),
           let fieldEditor = firstResponder as? NSTextView {
            fieldEditor.selectAll(nil)
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        requestClose()
    }

    private func requestClose() {
        if let onRequestClose {
            onRequestClose()
        } else {
            performClose(nil)
        }
    }

    private static func isCloseShortcut(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              event.charactersIgnoringModifiers?.lowercased() == "w"
        else {
            return false
        }

        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        return flags == .command
    }

    private static func isSelectAllShortcut(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              event.charactersIgnoringModifiers?.lowercased() == "a"
        else {
            return false
        }

        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        return flags == .command
    }
}

@MainActor
final class SettingsWindowController: NSWindowController {
    private static let minimumContentHeight: CGFloat = 300
    private static let maximumContentHeight: CGFloat = 680
    private static let screenEdgeInset: CGFloat = 8

    var onQuickAddShortcutChange: ((GlobalShortcut) -> Bool)?
    var onTrayShortcutChange: ((GlobalShortcut) -> Bool)?
    var onReturnToMenu: (() -> Void)?

    var isPresented: Bool {
        loadedWindow?.isVisible == true
    }

    private let reminderStore: ReminderStore
    private let settingsStore: AppSettingsStore
    private let launchAtLoginController: LaunchAtLoginController
    private var settingsPanel: SettingsPanel?
    private var viewModel: SettingsViewModel?
    private weak var anchorView: NSView?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var requestedContentHeight: CGFloat = 620
    private var presentationState: SettingsPresentationState = .hidden
    private var transitionGeneration = 0
    private var dismissalCompletions: [() -> Void] = []

    init(
        reminderStore: ReminderStore,
        settingsStore: AppSettingsStore,
        launchAtLoginController: LaunchAtLoginController
    ) {
        self.reminderStore = reminderStore
        self.settingsStore = settingsStore
        self.launchAtLoginController = launchAtLoginController
        super.init(window: nil)
    }

    func present(anchoredTo anchorView: NSView? = nil) {
        if let anchorView {
            self.anchorView = anchorView
        }

        let window = loadSettingsWindow()
        viewModel?.refresh()

        switch presentationState.beginPresentationRequest() {
        case .bringForward:
            window.makeKeyAndOrderFront(nil)
            return
        case .restoreAfterDismissal:
            restorePresentation(window)
            return
        case .animate:
            break
        }

        transitionGeneration += 1
        let generation = transitionGeneration
        resizeWindow(toContentHeight: requestedContentHeight)
        positionWindow()
        window.alphaValue = 0
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKey()
        configureOuterScrollView()
        (self.anchorView as? NSStatusBarButton)?.highlight(true)
        startOutsideClickMonitoring()

        window.contentView?.layoutSubtreeIfNeeded()
        DispatchQueue.main.async { [weak self] in
            DispatchQueue.main.async { [weak self] in
                self?.animatePresentation(generation: generation)
            }
        }
    }

    private func restorePresentation(_ window: SettingsPanel) {
        transitionGeneration += 1
        dismissalCompletions.removeAll()
        resizeWindow(toContentHeight: requestedContentHeight)
        positionWindow()
        window.alphaValue = 1
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKey()
        configureOuterScrollView()
        (anchorView as? NSStatusBarButton)?.highlight(true)
        startOutsideClickMonitoring()
        presentationState = .presented
    }

    func dismiss(animated: Bool = true, completion: (() -> Void)? = nil) {
        if let completion {
            dismissalCompletions.append(completion)
        }

        guard let window = loadedWindow,
              presentationState != .hidden,
              window.isVisible
        else {
            discardWindow()
            runDismissalCompletions()
            return
        }
        guard presentationState != .dismissing else {
            return
        }

        transitionGeneration += 1
        let generation = transitionGeneration
        presentationState = .dismissing
        stopOutsideClickMonitoring()

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard animated else {
            finishDismissal(generation: generation)
            return
        }

        let endFrame = SettingsPanelTransition.dismissedFrame(
            from: window.frame,
            reduceMotion: reduceMotion
        )
        NSAnimationContext.runAnimationGroup { context in
            context.duration = SettingsPanelTransition.dismissalDuration(reduceMotion: reduceMotion)
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().alphaValue = 0
            window.animator().setFrame(endFrame, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                self?.finishDismissal(generation: generation)
            }
        }
    }

    func closeBeforeTermination() {
        transitionGeneration += 1
        presentationState = .hidden
        dismissalCompletions.removeAll()
        (anchorView as? NSStatusBarButton)?.highlight(false)
        discardWindow()
    }

    private var loadedWindow: SettingsPanel? {
        settingsPanel
    }

    private func loadSettingsWindow() -> SettingsPanel {
        if let settingsPanel {
            return settingsPanel
        }

        let window = Self.makeWindow()
        let viewModel = SettingsViewModel(
            reminderStore: reminderStore,
            settingsStore: settingsStore,
            launchAtLoginController: launchAtLoginController,
            onQuickAddShortcutChange: { [weak self] shortcut in
                self?.onQuickAddShortcutChange?(shortcut) ?? false
            },
            onTrayShortcutChange: { [weak self] shortcut in
                self?.onTrayShortcutChange?(shortcut) ?? false
            },
            onPermissionRequestComplete: { [weak self] in
                self?.restoreAfterPermissionRequest()
            }
        )
        configure(window: window, viewModel: viewModel)
        self.window = window
        settingsPanel = window
        return window
    }

    private static func makeWindow() -> SettingsPanel {
        let window = SettingsPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: SettingsView.contentWidth,
                height: 620
            ),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .popUpMenu
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient, .ignoresCycle]
        window.hidesOnDeactivate = false
        window.animationBehavior = .none
        window.isMovableByWindowBackground = false
        window.isRestorable = false
        window.tabbingMode = .disallowed
        window.autorecalculatesKeyViewLoop = true
        return window
    }

    private func configure(window: SettingsPanel, viewModel: SettingsViewModel) {
        self.viewModel = viewModel
        window.onRequestClose = { [weak self] in
            self?.dismiss()
        }
        window.contentView = NSHostingView(rootView: SettingsView(
            model: viewModel,
            onReturnToMenu: { [weak self] in
                self?.returnToMenu()
            },
            onContentHeightChange: { [weak self] height in
                DispatchQueue.main.async { [weak self] in
                    self?.resizeWindow(toContentHeight: height)
                }
            }
        ))
    }

    private func returnToMenu() {
        dismiss { [weak self] in
            self?.onReturnToMenu?()
        }
    }

    private func restoreAfterPermissionRequest() {
        present(anchoredTo: anchorView)
    }

    private func animatePresentation(generation: Int) {
        guard generation == transitionGeneration,
              presentationState == .presenting,
              let window = loadedWindow,
              window.isVisible
        else {
            return
        }

        resizeWindow(toContentHeight: requestedContentHeight)
        positionWindow()

        let finalFrame = window.frame
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        window.setFrame(
            SettingsPanelTransition.presentedStartFrame(
                from: finalFrame,
                reduceMotion: reduceMotion
            ),
            display: true
        )

        NSAnimationContext.runAnimationGroup { context in
            context.duration = SettingsPanelTransition.presentationDuration(reduceMotion: reduceMotion)
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
            window.animator().setFrame(finalFrame, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self,
                      generation == transitionGeneration,
                      presentationState == .presenting,
                      let window = self.loadedWindow
                else {
                    return
                }

                presentationState = .presented
                window.alphaValue = 1
                window.setFrame(finalFrame, display: true)
            }
        }
    }

    private func finishDismissal(generation: Int) {
        guard generation == transitionGeneration,
              presentationState == .dismissing,
              let window = loadedWindow
        else {
            return
        }

        window.orderOut(nil)
        window.alphaValue = 1
        (anchorView as? NSStatusBarButton)?.highlight(false)
        presentationState = .hidden
        discardWindow()
        runDismissalCompletions()
    }

    private func runDismissalCompletions() {
        let completions = dismissalCompletions
        dismissalCompletions.removeAll()
        completions.forEach { $0() }
    }

    private func resizeWindow(toContentHeight requestedHeight: CGFloat) {
        requestedContentHeight = requestedHeight
        guard let window = loadedWindow else {
            return
        }

        configureOuterScrollView()

        guard presentationState != .presented,
              presentationState != .dismissing
        else {
            return
        }

        let targetHeight = min(
            max(requestedHeight, Self.minimumContentHeight),
            maximumAvailableContentHeight
        )
        guard abs(window.frame.height - targetHeight) > 0.5 else {
            return
        }

        let targetSize = NSSize(width: SettingsView.contentWidth, height: targetHeight)
        if window.isVisible {
            window.setFrame(positionedFrame(for: targetSize), display: true)
        } else {
            window.setContentSize(targetSize)
        }
        configureOuterScrollView()
    }

    private var maximumAvailableContentHeight: CGFloat {
        let visibleHeight = anchorView?.window?.screen?.visibleFrame.height
            ?? loadedWindow?.screen?.visibleFrame.height
        guard let visibleHeight else {
            return Self.maximumContentHeight
        }
        return min(Self.maximumContentHeight, visibleHeight - (Self.screenEdgeInset * 2))
    }

    private func configureOuterScrollView() {
        DispatchQueue.main.async { [weak self] in
            guard let contentView = self?.loadedWindow?.contentView else {
                return
            }
            let outerScrollView = contentView.descendants(of: NSScrollView.self)
                .max { $0.frame.width < $1.frame.width }
            outerScrollView?.scrollerStyle = .overlay
            outerScrollView?.autohidesScrollers = true
            outerScrollView?.hasVerticalScroller = false
        }
    }

    private func positionWindow() {
        guard let window = loadedWindow else {
            return
        }
        window.setFrame(positionedFrame(for: window.frame.size), display: true)
    }

    private func positionedFrame(for panelSize: NSSize) -> NSRect {
        guard let window = loadedWindow else {
            return NSRect(origin: .zero, size: panelSize)
        }

        if let anchorView,
           let anchorWindow = anchorView.window {
            let anchorRect = anchorWindow.convertToScreen(
                anchorView.convert(anchorView.bounds, to: nil)
            )
            let visibleFrame = anchorWindow.screen?.visibleFrame
                ?? NSScreen.screens.first(where: { $0.frame.intersects(anchorRect) })?.visibleFrame
                ?? NSScreen.main?.visibleFrame
            if let visibleFrame {
                return SettingsPanelPlacement.frame(
                    anchorRect: anchorRect,
                    panelSize: panelSize,
                    visibleFrame: visibleFrame
                )
            }
        }

        if window.isVisible {
            return NSRect(
                x: window.frame.midX - (panelSize.width / 2),
                y: window.frame.maxY - panelSize.height,
                width: panelSize.width,
                height: panelSize.height
            )
        }

        let visibleFrame = window.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? .zero
        return NSRect(
            x: visibleFrame.midX - (panelSize.width / 2),
            y: visibleFrame.midY - (panelSize.height / 2),
            width: panelSize.width,
            height: panelSize.height
        )
    }

    private func startOutsideClickMonitoring() {
        #if DEBUG
        guard !ProcessInfo.processInfo.arguments.contains("--ui-testing") else {
            return
        }
        #endif

        guard localMouseMonitor == nil, globalMouseMonitor == nil else {
            return
        }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self, let window = self.loadedWindow else {
                return event
            }
            if Self.shouldDismiss(for: event.window, panelWindow: window) {
                self.dismiss()
            }
            return event
        }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            Task { @MainActor in
                self?.dismiss()
            }
        }
    }

    private func discardWindow() {
        guard let window = loadedWindow else {
            return
        }
        stopOutsideClickMonitoring()
        window.onRequestClose = nil
        window.contentView = nil
        viewModel = nil
        window.close()
        self.window = nil
        settingsPanel = nil
    }

    static func shouldDismiss(for eventWindow: NSWindow?, panelWindow: NSWindow) -> Bool {
        var candidate = eventWindow
        while let window = candidate {
            if window === panelWindow {
                return false
            }
            candidate = window.parent
        }
        return true
    }

    private func stopOutsideClickMonitoring() {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
        }
    }
}

enum SettingsPresentationState: Equatable {
    case hidden
    case presenting
    case presented
    case dismissing

    mutating func beginPresentationRequest() -> SettingsPresentationAction {
        switch self {
        case .hidden:
            self = .presenting
            return .animate
        case .dismissing:
            self = .presenting
            return .restoreAfterDismissal
        case .presenting, .presented:
            return .bringForward
        }
    }
}

enum SettingsPresentationAction: Equatable {
    case animate
    case restoreAfterDismissal
    case bringForward
}

enum SettingsPanelTransition {
    private static let verticalOffset: CGFloat = 8
    private static let standardPresentationDuration: TimeInterval = 0.20
    private static let standardDismissalDuration: TimeInterval = 0.16
    private static let reducedMotionDuration: TimeInterval = 0.10

    static func presentationDuration(reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? reducedMotionDuration : standardPresentationDuration
    }

    static func dismissalDuration(reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? reducedMotionDuration : standardDismissalDuration
    }

    static func presentedStartFrame(from finalFrame: NSRect, reduceMotion: Bool) -> NSRect {
        offsetFrame(finalFrame, reduceMotion: reduceMotion)
    }

    static func dismissedFrame(from presentedFrame: NSRect, reduceMotion: Bool) -> NSRect {
        offsetFrame(presentedFrame, reduceMotion: reduceMotion)
    }

    private static func offsetFrame(_ frame: NSRect, reduceMotion: Bool) -> NSRect {
        guard !reduceMotion else {
            return frame
        }
        return frame.offsetBy(dx: 0, dy: verticalOffset)
    }
}

enum SettingsPanelPlacement {
    private static let edgeInset: CGFloat = 8
    private static let anchorGap: CGFloat = 6

    static func frame(
        anchorRect: NSRect,
        panelSize: NSSize,
        visibleFrame: NSRect
    ) -> NSRect {
        let proposedX = anchorRect.midX - (panelSize.width / 2)
        let minimumX = visibleFrame.minX + edgeInset
        let maximumX = visibleFrame.maxX - panelSize.width - edgeInset
        let x = min(max(proposedX, minimumX), max(minimumX, maximumX))

        let proposedY = anchorRect.minY - panelSize.height - anchorGap
        let minimumY = visibleFrame.minY + edgeInset
        let maximumY = visibleFrame.maxY - panelSize.height - edgeInset
        let y = min(max(proposedY, minimumY), max(minimumY, maximumY))

        return NSRect(origin: NSPoint(x: x, y: y), size: panelSize)
    }
}

private extension NSView {
    func descendants<View: NSView>(of type: View.Type) -> [View] {
        subviews.flatMap { subview in
            let match = (subview as? View).map { [$0] } ?? []
            return match + subview.descendants(of: type)
        }
    }
}
