import AppKit
import Carbon
import Foundation

struct HotKey: Codable, Hashable, Sendable {
    struct Modifiers: OptionSet, Codable, Hashable, Sendable {
        let rawValue: Int

        static let command = Modifiers(rawValue: 1 << 0)
        static let option = Modifiers(rawValue: 1 << 1)
        static let control = Modifiers(rawValue: 1 << 2)
        static let shift = Modifiers(rawValue: 1 << 3)
    }

    var keyCode: UInt32
    var modifiers: Modifiers

    static let defaultRecording = HotKey(keyCode: UInt32(kVK_ANSI_Semicolon), modifiers: [.command, .shift])
    static let defaultCheckpoint = HotKey(keyCode: UInt32(kVK_ANSI_Quote), modifiers: [.command, .shift])

    var carbonModifiers: UInt32 {
        var flags: UInt32 = 0
        if modifiers.contains(.command) { flags |= UInt32(cmdKey) }
        if modifiers.contains(.option) { flags |= UInt32(optionKey) }
        if modifiers.contains(.control) { flags |= UInt32(controlKey) }
        if modifiers.contains(.shift) { flags |= UInt32(shiftKey) }
        return flags
    }

    var eventModifiers: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers.contains(.command) { flags.insert(.command) }
        if modifiers.contains(.option) { flags.insert(.option) }
        if modifiers.contains(.control) { flags.insert(.control) }
        if modifiers.contains(.shift) { flags.insert(.shift) }
        return flags
    }

    var displayString: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }
        parts.append(Self.keyLabel(for: Int(keyCode)))
        return parts.joined()
    }

    init(keyCode: UInt32, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init?(event: NSEvent) {
        let allowed = event.modifierFlags.intersection([.command, .option, .control, .shift])
        var modifiers: Modifiers = []
        if allowed.contains(.command) { modifiers.insert(.command) }
        if allowed.contains(.option) { modifiers.insert(.option) }
        if allowed.contains(.control) { modifiers.insert(.control) }
        if allowed.contains(.shift) { modifiers.insert(.shift) }
        self.init(keyCode: UInt32(event.keyCode), modifiers: modifiers)
    }

    private static func keyLabel(for keyCode: Int) -> String {
        if let named = Self.namedKeyMap[keyCode] {
            return named
        }
        if let alphaNumeric = Self.alphaNumericKeyMap[keyCode] {
            return alphaNumeric
        }
        if let symbol = Self.specialKeyMap[keyCode] {
            return symbol
        }
        return "Key \(keyCode)"
    }

    private static let namedKeyMap: [Int: String] = [
        kVK_Return: "↩",
        kVK_Space: "Space",
        kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦",
        kVK_Escape: "⎋",
        kVK_Tab: "⇥",
        kVK_LeftArrow: "←",
        kVK_RightArrow: "→",
        kVK_UpArrow: "↑",
        kVK_DownArrow: "↓"
    ]

    private static let alphaNumericKeyMap: [Int: String] = [
        kVK_ANSI_A: "A",
        kVK_ANSI_B: "B",
        kVK_ANSI_C: "C",
        kVK_ANSI_D: "D",
        kVK_ANSI_E: "E",
        kVK_ANSI_F: "F",
        kVK_ANSI_G: "G",
        kVK_ANSI_H: "H",
        kVK_ANSI_I: "I",
        kVK_ANSI_J: "J",
        kVK_ANSI_K: "K",
        kVK_ANSI_L: "L",
        kVK_ANSI_M: "M",
        kVK_ANSI_N: "N",
        kVK_ANSI_O: "O",
        kVK_ANSI_P: "P",
        kVK_ANSI_Q: "Q",
        kVK_ANSI_R: "R",
        kVK_ANSI_S: "S",
        kVK_ANSI_T: "T",
        kVK_ANSI_U: "U",
        kVK_ANSI_V: "V",
        kVK_ANSI_W: "W",
        kVK_ANSI_X: "X",
        kVK_ANSI_Y: "Y",
        kVK_ANSI_Z: "Z",
        kVK_ANSI_0: "0",
        kVK_ANSI_1: "1",
        kVK_ANSI_2: "2",
        kVK_ANSI_3: "3",
        kVK_ANSI_4: "4",
        kVK_ANSI_5: "5",
        kVK_ANSI_6: "6",
        kVK_ANSI_7: "7",
        kVK_ANSI_8: "8",
        kVK_ANSI_9: "9"
    ]

    private static let specialKeyMap: [Int: String] = [
        kVK_ANSI_Minus: "-",
        kVK_ANSI_Equal: "=",
        kVK_ANSI_LeftBracket: "[",
        kVK_ANSI_RightBracket: "]",
        kVK_ANSI_Backslash: "\\",
        kVK_ANSI_Semicolon: ";",
        kVK_ANSI_Quote: "'",
        kVK_ANSI_Comma: ",",
        kVK_ANSI_Period: ".",
        kVK_ANSI_Slash: "/",
        kVK_ANSI_Grave: "`"
    ]
}
