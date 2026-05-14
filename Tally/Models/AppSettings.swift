import AppKit
import Carbon
import Foundation

enum MenuBarBadgeStyle: String, CaseIterable, Identifiable {
    case trailingCount
    case iconBadge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .trailingCount:
            return "Count"
        case .iconBadge:
            return "Badge"
        }
    }
}

struct ShortcutModifiers: OptionSet, Codable, Equatable {
    let rawValue: UInt

    static let control = ShortcutModifiers(rawValue: 1 << 0)
    static let option = ShortcutModifiers(rawValue: 1 << 1)
    static let shift = ShortcutModifiers(rawValue: 1 << 2)
    static let command = ShortcutModifiers(rawValue: 1 << 3)
}

struct GlobalShortcut: Codable, Equatable {
    let keyEquivalent: String
    let keyCode: UInt16
    let modifiers: ShortcutModifiers

    static let defaultTrayValue = GlobalShortcut(
        keyEquivalent: "t",
        keyCode: UInt16(kVK_ANSI_T),
        modifiers: [.control, .command]
    )

    static let defaultQuickAddValue = GlobalShortcut(
        keyEquivalent: " ",
        keyCode: UInt16(kVK_Space),
        modifiers: [.option]
    )

    static let invalidValue = GlobalShortcut(
        keyEquivalent: "",
        keyCode: UInt16.max,
        modifiers: []
    )

    static let defaultValue = defaultTrayValue

    var carbonModifierFlags: UInt32 {
        var flags: UInt32 = 0

        if modifiers.contains(.command) {
            flags |= UInt32(cmdKey)
        }

        if modifiers.contains(.control) {
            flags |= UInt32(controlKey)
        }

        if modifiers.contains(.option) {
            flags |= UInt32(optionKey)
        }

        if modifiers.contains(.shift) {
            flags |= UInt32(shiftKey)
        }

        return flags
    }

    var menuModifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []

        if modifiers.contains(.command) {
            flags.insert(.command)
        }

        if modifiers.contains(.control) {
            flags.insert(.control)
        }

        if modifiers.contains(.option) {
            flags.insert(.option)
        }

        if modifiers.contains(.shift) {
            flags.insert(.shift)
        }

        return flags
    }

    var displayTitle: String {
        guard isValid else {
            return "Invalid"
        }

        var title = ""

        if modifiers.contains(.control) {
            title += "⌃"
        }

        if modifiers.contains(.option) {
            title += "⌥"
        }

        if modifiers.contains(.shift) {
            title += "⇧"
        }

        if modifiers.contains(.command) {
            title += "⌘"
        }

        return title + displayKeyTitle
    }

    var isValid: Bool {
        let isSpaceShortcut = keyCode == UInt16(kVK_Space) && keyEquivalent == " "

        guard keyEquivalent.count == 1,
              let scalar = keyEquivalent.unicodeScalars.first,
              !CharacterSet.controlCharacters.contains(scalar),
              isSpaceShortcut || !CharacterSet.whitespacesAndNewlines.contains(scalar)
        else {
            return false
        }

        return modifiers.intersection([.command, .control, .option]).isEmpty == false
    }

    static func candidate(from event: NSEvent) -> GlobalShortcut? {
        guard event.type == .keyDown,
              event.specialKey == nil,
              let keyEquivalent = event.charactersIgnoringModifiers?.lowercased(),
              keyEquivalent.count == 1
        else {
            return nil
        }

        let modifiers = ShortcutModifiers(eventModifierFlags: event.modifierFlags)
        let candidate = GlobalShortcut(
            keyEquivalent: keyEquivalent,
            keyCode: event.keyCode,
            modifiers: modifiers
        )

        return candidate.isValid ? candidate : nil
    }

    private var displayKeyTitle: String {
        keyCode == UInt16(kVK_Space) ? "Space" : keyEquivalent.uppercased()
    }
}

private extension ShortcutModifiers {
    init(eventModifierFlags: NSEvent.ModifierFlags) {
        let flags = eventModifierFlags.intersection([.command, .control, .option, .shift])
        var modifiers: ShortcutModifiers = []

        if flags.contains(.command) {
            modifiers.insert(.command)
        }

        if flags.contains(.control) {
            modifiers.insert(.control)
        }

        if flags.contains(.option) {
            modifiers.insert(.option)
        }

        if flags.contains(.shift) {
            modifiers.insert(.shift)
        }

        self = modifiers
    }
}
