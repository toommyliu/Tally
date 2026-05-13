import AppKit
import SwiftUI

@MainActor
final class QuickAddWindowController: NSObject, NSWindowDelegate {
    private static let windowSize = NSSize(width: 440, height: 174)

    private let reminderStore: ReminderStore
    private var window: NSWindow?

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

        center(window, size: Self.windowSize)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func close() {
        window?.close()
        resetWindow()
    }

    func windowWillClose(_ notification: Notification) {
        resetWindow()
    }

    func windowDidResignKey(_ notification: Notification) {
        guard window?.isVisible == true else {
            return
        }

        close()
    }

    private func resetWindow() {
        window?.delegate = nil
        window?.contentViewController = nil
        window = nil
    }

    private func makeWindow() -> NSWindow {
        let contentView = QuickAddWindowView(
            onCancel: { [weak self] in
                self?.close()
            },
            onSubmit: { [weak self] input, notes in
                guard let self else {
                    return
                }

                Task {
                    await self.reminderStore.addReminder(from: input, notes: notes)
                    self.close()
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

        panel.contentViewController = NSHostingController(rootView: contentView)
        panel.delegate = self
        panel.setContentSize(Self.windowSize)
        panel.contentMinSize = Self.windowSize
        panel.contentMaxSize = Self.windowSize
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true

        return panel
    }

    private func center(_ window: NSWindow, size: NSSize) {
        let screen = screenContainingMouse() ?? NSScreen.main

        guard let visibleFrame = screen?.visibleFrame else {
            window.setFrame(NSRect(origin: .zero, size: size), display: false)
            window.center()
            return
        }

        let origin = NSPoint(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.midY - size.height / 2
        )
        window.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    private func screenContainingMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { screen in
            screen.frame.contains(mouseLocation)
        }
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
