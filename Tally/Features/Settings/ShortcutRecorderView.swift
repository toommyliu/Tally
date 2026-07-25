import AppKit
import Carbon
import SwiftUI

struct ShortcutRecorderView: NSViewRepresentable {
    let shortcut: GlobalShortcut
    let activationRequestID: Int
    let onFocus: () -> Void
    let onMoveFocus: (Bool) -> Void
    let onRecord: (NSEvent) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(shortcut: shortcut)
    }

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton()
        button.isBordered = false
        button.focusRingType = .none
        button.font = .systemFont(ofSize: 11.5, weight: .medium)
        button.setButtonType(.momentaryPushIn)
        button.target = button
        button.action = #selector(ShortcutRecorderButton.startRecording)
        button.onFocus = onFocus
        button.onMoveFocus = onMoveFocus
        button.onRecordingChanged = { isRecording in
            context.coordinator.isRecording = isRecording
            Self.updateTitle(
                for: button,
                shortcut: context.coordinator.shortcut,
                isRecording: isRecording
            )
        }
        button.onKeyDown = { event in
            guard event.keyCode != UInt16(kVK_Escape) else {
                button.stopRecording()
                return
            }

            onRecord(event)
            button.stopRecording()
        }
        Self.updateTitle(for: button, shortcut: shortcut, isRecording: false)
        return button
    }

    func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
        context.coordinator.shortcut = shortcut
        button.onFocus = onFocus
        button.onMoveFocus = onMoveFocus
        Self.updateTitle(
            for: button,
            shortcut: shortcut,
            isRecording: context.coordinator.isRecording
        )

        if context.coordinator.lastActivationRequestID != activationRequestID {
            context.coordinator.lastActivationRequestID = activationRequestID
            DispatchQueue.main.async { [weak button] in
                guard let button,
                      button.window != nil
                else {
                    return
                }

                button.startRecording()
            }
        }
    }

    private static func updateTitle(
        for button: ShortcutRecorderButton,
        shortcut: GlobalShortcut,
        isRecording: Bool
    ) {
        let showsInvalidState = !shortcut.isValid && !isRecording
        button.title = isRecording ? "Press keys…" : shortcut.displayTitle
        button.showsInvalidState = showsInvalidState
        button.updateTitleAppearance()
        button.toolTip = showsInvalidState ? "Record a new shortcut or reset to the default." : nil
        button.setAccessibilityLabel("Record keyboard shortcut")
        button.setAccessibilityValue(isRecording ? "Waiting for shortcut" : shortcut.displayTitle)
    }

    final class Coordinator {
        var shortcut: GlobalShortcut
        var isRecording = false
        var lastActivationRequestID = 0

        init(shortcut: GlobalShortcut) {
            self.shortcut = shortcut
        }
    }
}

final class ShortcutRecorderButton: NSButton {
    var onRecordingChanged: ((Bool) -> Void)?
    var onKeyDown: ((NSEvent) -> Void)?
    var onFocus: (() -> Void)?
    var onMoveFocus: ((Bool) -> Void)?
    var showsInvalidState = false {
        didSet { updateAppearance() }
    }
    private var isRecording = false {
        didSet { updateAppearance() }
    }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureAppearance()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureAppearance()
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func becomeFirstResponder() -> Bool {
        let didBecomeFirstResponder = super.becomeFirstResponder()
        if didBecomeFirstResponder {
            onFocus?()
        }
        return didBecomeFirstResponder
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
        updateTitleAppearance()
    }

    @objc func startRecording() {
        isRecording = true
        window?.makeFirstResponder(self)
        onRecordingChanged?(true)
    }

    func stopRecording() {
        isRecording = false
        onRecordingChanged?(false)
    }

    override func resignFirstResponder() -> Bool {
        stopRecording()
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        if isRecording {
            onKeyDown?(event)
            return
        }

        switch Int(event.keyCode) {
        case kVK_Tab:
            onMoveFocus?(!event.modifierFlags.contains(.shift))
        case kVK_Return, kVK_ANSI_KeypadEnter, kVK_Space:
            startRecording()
        default:
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let borderColor: NSColor
        if showsInvalidState {
            borderColor = .systemRed
        } else {
            borderColor = .separatorColor
        }

        let lineWidth: CGFloat = 0.5
        let borderRect = bounds.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
        let borderPath = NSBezierPath(roundedRect: borderRect, xRadius: 6, yRadius: 6)
        borderPath.lineWidth = lineWidth
        borderColor.withAlphaComponent(0.55).setStroke()
        borderPath.stroke()
    }

    func updateTitleAppearance() {
        let font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        let foregroundColor: NSColor
        if showsInvalidState {
            foregroundColor = .systemRed
        } else if isRecording {
            foregroundColor = .labelColor
        } else {
            foregroundColor = .labelColor
        }

        attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: font,
                .foregroundColor: foregroundColor
            ]
        )
    }

    private func configureAppearance() {
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.cornerCurve = .continuous
        updateAppearance()
    }

    private func updateAppearance() {
        guard let layer else {
            return
        }

        let backgroundColor: NSColor
        if isRecording {
            backgroundColor = .keyboardFocusIndicatorColor.withAlphaComponent(0.12)
        } else {
            backgroundColor = .labelColor.withAlphaComponent(0.035)
        }

        layer.borderWidth = 0
        layer.backgroundColor = backgroundColor.cgColor
        needsDisplay = true
    }
}
