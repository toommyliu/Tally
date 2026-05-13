import Carbon.HIToolbox
import Foundation

final class HotKeyController {
    private let hotKeyID = EventHotKeyID(signature: fourCharacterCode("Taly"), id: 1)
    private let keyCode = UInt32(kVK_Space)
    private let modifiers = UInt32(optionKey)
    private let action: @MainActor () -> Void

    private var eventHandler: EventHandlerRef?
    private var eventHotKey: EventHotKeyRef?

    init(action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    deinit {
        unregister()
    }

    func register() {
        guard eventHotKey == nil else {
            return
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else {
                    return noErr
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
                    return noErr
                }

                Task { @MainActor in
                    controller.action()
                }

                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )

        RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &eventHotKey
        )
    }

    private func unregister() {
        if let eventHotKey {
            UnregisterEventHotKey(eventHotKey)
        }

        if let eventHandler {
            RemoveEventHandler(eventHandler)
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
