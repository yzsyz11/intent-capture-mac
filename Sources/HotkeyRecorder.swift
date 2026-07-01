import Carbon
import AppKit
import Foundation

struct HotkeyDefinition: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let rawValue: String

    static let controlModifier = UInt32(controlKey)
    static let optionModifier = UInt32(optionKey)
    static let commandModifier = UInt32(cmdKey)
    static let shiftModifier = UInt32(shiftKey)

    static let defaultAction = HotkeyDefinition(keyCode: UInt32(kVK_ANSI_S), modifiers: controlModifier | optionModifier, rawValue: "control+option+s")
    static let defaultPanel = HotkeyDefinition(keyCode: UInt32(kVK_ANSI_W), modifiers: controlModifier | optionModifier, rawValue: "control+option+w")
    static let defaultClipboardDock = HotkeyDefinition(keyCode: UInt32(kVK_ANSI_D), modifiers: commandModifier, rawValue: "command+d")

    init(keyCode: UInt32, modifiers: UInt32, rawValue: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.rawValue = rawValue
    }

    init?(event: NSEvent) {
        let carbonModifiers = Self.carbonModifiers(from: event.modifierFlags)
        guard carbonModifiers != 0 else { return nil }
        let keyCode = UInt32(event.keyCode)
        let keyName = Self.keyName(for: keyCode)
        guard !keyName.isEmpty else { return nil }
        let rawValue = Self.rawValue(keyCode: keyCode, modifiers: carbonModifiers)
        self.init(keyCode: keyCode, modifiers: carbonModifiers, rawValue: rawValue)
    }

    init?(rawValue: String) {
        let parts = rawValue.lowercased().split(separator: "+").map(String.init)
        guard let key = parts.last else { return nil }

        var modifiers: UInt32 = 0
        for part in parts.dropLast() {
            switch part {
            case "control", "ctrl": modifiers |= Self.controlModifier
            case "option", "alt": modifiers |= Self.optionModifier
            case "command", "cmd": modifiers |= Self.commandModifier
            case "shift": modifiers |= Self.shiftModifier
            default: break
            }
        }

        guard let keyCode = Self.keyCode(for: key) else { return nil }
        self.init(keyCode: keyCode, modifiers: modifiers, rawValue: rawValue.lowercased())
    }

    var displayText: String {
        var pieces: [String] = []
        if modifiers & Self.controlModifier != 0 { pieces.append("⌃") }
        if modifiers & Self.optionModifier != 0 { pieces.append("⌥") }
        if modifiers & Self.shiftModifier != 0 { pieces.append("⇧") }
        if modifiers & Self.commandModifier != 0 { pieces.append("⌘") }
        pieces.append(Self.keyName(for: keyCode))
        return pieces.joined()
    }

    private static func keyCode(for key: String) -> UInt32? {
        switch key {
        case "a": return UInt32(kVK_ANSI_A)
        case "b": return UInt32(kVK_ANSI_B)
        case "c": return UInt32(kVK_ANSI_C)
        case "d": return UInt32(kVK_ANSI_D)
        case "e": return UInt32(kVK_ANSI_E)
        case "f": return UInt32(kVK_ANSI_F)
        case "g": return UInt32(kVK_ANSI_G)
        case "h": return UInt32(kVK_ANSI_H)
        case "i": return UInt32(kVK_ANSI_I)
        case "j": return UInt32(kVK_ANSI_J)
        case "k": return UInt32(kVK_ANSI_K)
        case "l": return UInt32(kVK_ANSI_L)
        case "m": return UInt32(kVK_ANSI_M)
        case "n": return UInt32(kVK_ANSI_N)
        case "s": return UInt32(kVK_ANSI_S)
        case "t": return UInt32(kVK_ANSI_T)
        case "u": return UInt32(kVK_ANSI_U)
        case "v": return UInt32(kVK_ANSI_V)
        case "w": return UInt32(kVK_ANSI_W)
        case "x": return UInt32(kVK_ANSI_X)
        case "y": return UInt32(kVK_ANSI_Y)
        case "z": return UInt32(kVK_ANSI_Z)
        case "o": return UInt32(kVK_ANSI_O)
        case "p": return UInt32(kVK_ANSI_P)
        case "0": return UInt32(kVK_ANSI_0)
        case "1": return UInt32(kVK_ANSI_1)
        case "2": return UInt32(kVK_ANSI_2)
        case "3": return UInt32(kVK_ANSI_3)
        case "4": return UInt32(kVK_ANSI_4)
        case "5": return UInt32(kVK_ANSI_5)
        case "6": return UInt32(kVK_ANSI_6)
        case "7": return UInt32(kVK_ANSI_7)
        case "8": return UInt32(kVK_ANSI_8)
        case "9": return UInt32(kVK_ANSI_9)
        default: return nil
        }
    }

    private static func keyName(for code: UInt32) -> String {
        switch Int(code) {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        default: return "\(code)"
        }
    }

    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.control) { modifiers |= controlModifier }
        if flags.contains(.option) { modifiers |= optionModifier }
        if flags.contains(.command) { modifiers |= commandModifier }
        if flags.contains(.shift) { modifiers |= shiftModifier }
        return modifiers
    }

    private static func rawValue(keyCode: UInt32, modifiers: UInt32) -> String {
        var pieces: [String] = []
        if modifiers & controlModifier != 0 { pieces.append("control") }
        if modifiers & optionModifier != 0 { pieces.append("option") }
        if modifiers & shiftModifier != 0 { pieces.append("shift") }
        if modifiers & commandModifier != 0 { pieces.append("command") }
        pieces.append(keyName(for: keyCode).lowercased())
        return pieces.joined(separator: "+")
    }
}

final class HotkeyRecorderButton: NSButton {
    var hotkey: HotkeyDefinition {
        didSet { refreshTitle() }
    }
    var onChange: ((HotkeyDefinition) -> Void)?

    private var recording = false

    init(hotkey: HotkeyDefinition) {
        self.hotkey = hotkey
        super.init(frame: .zero)
        bezelStyle = .rounded
        target = self
        action = #selector(startRecording)
        refreshTitle()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    @objc private func startRecording() {
        recording = true
        title = "按下新的组合键..."
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard recording else {
            super.keyDown(with: event)
            return
        }

        if event.keyCode == UInt16(kVK_Escape) {
            recording = false
            refreshTitle()
            return
        }

        guard let next = HotkeyDefinition(event: event) else {
            NSSound.beep()
            title = "需要包含 ⌃/⌥/⇧/⌘"
            return
        }

        recording = false
        hotkey = next
        onChange?(next)
        window?.makeFirstResponder(nil)
    }

    override func resignFirstResponder() -> Bool {
        recording = false
        refreshTitle()
        return super.resignFirstResponder()
    }

    private func refreshTitle() {
        title = hotkey.displayText
        toolTip = "点击后按下新的键盘快捷键，Esc 取消"
    }
}
