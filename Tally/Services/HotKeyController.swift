import Carbon.HIToolbox
import Foundation
import OSLog

final class HotKeyController {
    private static let logger = Logger(subsystem: "com.tommyliu.Tally", category: "HotKeyController")

    private let hotKeyID: EventHotKeyID
    private let action: @MainActor () -> Void
    private var keyCode: UInt32
    private var modifierFlags: UInt32
    private var hasValidShortcut: Bool
    private var isEnabled = true

    private var eventHandler: EventHandlerRef?
    private var eventHotKey: EventHotKeyRef?

    init(
        id: UInt32,
        shortcut: GlobalShortcut,
        action: @escaping @MainActor () -> Void
    ) {
        self.hotKeyID = EventHotKeyID(signature: fourCharacterCode("Taly"), id: id)
        self.keyCode = UInt32(shortcut.keyCode)
        self.modifierFlags = shortcut.carbonModifierFlags
        self.hasValidShortcut = shortcut.isValid
        self.action = action
        installEventHandler()
        _ = register()
    }

    init(id: UInt32, keyCode: UInt32, modifierFlags: UInt32, action: @escaping @MainActor () -> Void) {
        self.hotKeyID = EventHotKeyID(signature: fourCharacterCode("Taly"), id: id)
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags
        self.hasValidShortcut = true
        self.action = action
        installEventHandler()
        _ = register()
    }

    deinit {
        unregister()
        removeEventHandler()
    }

    @discardableResult
    func applyShortcut(_ shortcut: GlobalShortcut) -> Bool {
        guard shortcut.isValid else {
            return false
        }

        let previousKeyCode = keyCode
        let previousModifierFlags = modifierFlags
        let previousHasValidShortcut = hasValidShortcut
        unregister()
        keyCode = UInt32(shortcut.keyCode)
        modifierFlags = shortcut.carbonModifierFlags
        hasValidShortcut = true

        guard !isEnabled || register() else {
            keyCode = previousKeyCode
            modifierFlags = previousModifierFlags
            hasValidShortcut = previousHasValidShortcut
            if previousHasValidShortcut {
                _ = register()
            }
            return false
        }

        return true
    }

    func setEnabled(_ isEnabled: Bool) {
        self.isEnabled = isEnabled

        if isEnabled {
            _ = register()
        } else {
            unregister()
        }
    }

    private func installEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, userData in
                guard let event, let userData else {
                    return OSStatus(eventNotHandledErr)
                }

                let controller = Unmanaged<HotKeyController>
                    .fromOpaque(userData)
                    .takeUnretainedValue()

                var pressedHotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &pressedHotKeyID
                )

                guard status == noErr, pressedHotKeyID == controller.hotKeyID else {
                    return OSStatus(eventNotHandledErr)
                }

                DispatchQueue.main.async {
                    controller.action()
                }

                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )

        if status != noErr {
            Self.logger.error("Failed to install hotkey handler id=\(self.hotKeyID.id, privacy: .public) status=\(status, privacy: .public)")
        }
    }

    @discardableResult
    private func register() -> Bool {
        guard isEnabled else {
            return true
        }

        guard hasValidShortcut else {
            Self.logger.error("Skipping invalid hotkey id=\(self.hotKeyID.id, privacy: .public)")
            return false
        }

        guard eventHotKey == nil else {
            return true
        }

        let status = RegisterEventHotKey(
            keyCode,
            modifierFlags,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &eventHotKey
        )

        if status != noErr {
            Self.logger.error("Failed to register hotkey id=\(self.hotKeyID.id, privacy: .public) keyCode=\(self.keyCode, privacy: .public) modifiers=\(self.modifierFlags, privacy: .public) status=\(status, privacy: .public)")
            return false
        }

        Self.logger.notice("Registered hotkey id=\(self.hotKeyID.id, privacy: .public) keyCode=\(self.keyCode, privacy: .public) modifiers=\(self.modifierFlags, privacy: .public)")
        return true
    }

    private func unregister() {
        if let eventHotKey {
            UnregisterEventHotKey(eventHotKey)
            self.eventHotKey = nil
        }
    }

    private func removeEventHandler() {
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }
}

private func fourCharacterCode(_ value: String) -> OSType {
    value.utf8.reduce(0) { result, character in
        (result << 8) + OSType(character)
    }
}

private func == (lhs: EventHotKeyID, rhs: EventHotKeyID) -> Bool {
    lhs.signature == rhs.signature && lhs.id == rhs.id
}
