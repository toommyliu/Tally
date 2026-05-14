import AppKit
import Carbon
import SwiftUI

struct ShortcutRecorderView: NSViewRepresentable {
    let shortcut: GlobalShortcut
    let onRecord: (NSEvent) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(shortcut: shortcut)
    }

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton()
        button.bezelStyle = .rounded
        button.setButtonType(.momentaryPushIn)
        button.target = button
        button.action = #selector(ShortcutRecorderButton.startRecording)
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
        Self.updateTitle(
            for: button,
            shortcut: shortcut,
            isRecording: context.coordinator.isRecording
        )
    }

    private static func updateTitle(
        for button: ShortcutRecorderButton,
        shortcut: GlobalShortcut,
        isRecording: Bool
    ) {
        let showsInvalidState = !shortcut.isValid && !isRecording
        button.title = isRecording ? "Type shortcut" : shortcut.displayTitle
        button.contentTintColor = showsInvalidState ? .systemRed : nil
        button.toolTip = showsInvalidState ? "Record a new shortcut or reset to the default." : nil
    }

    final class Coordinator {
        var shortcut: GlobalShortcut
        var isRecording = false

        init(shortcut: GlobalShortcut) {
            self.shortcut = shortcut
        }
    }
}

final class ShortcutRecorderButton: NSButton {
    var onRecordingChanged: ((Bool) -> Void)?
    var onKeyDown: ((NSEvent) -> Void)?
    private var isRecording = false

    override var acceptsFirstResponder: Bool {
        true
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
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        onKeyDown?(event)
    }
}
