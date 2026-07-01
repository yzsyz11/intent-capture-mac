import AppKit
import Foundation

final class AppSettings {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard
    private let defaultSaveDirectory = URL(fileURLWithPath: "/Users/a1/Downloads/截图", isDirectory: true)

    var recentAction: CaptureAction {
        get {
            let raw = defaults.string(forKey: "recentAction") ?? CaptureAction.screenshotCopy.rawValue
            return CaptureAction(rawValue: raw) ?? .screenshotCopy
        }
        set { defaults.set(newValue.rawValue, forKey: "recentAction") }
    }

    var actionHotkey: HotkeyDefinition {
        get { HotkeyDefinition(rawValue: defaults.string(forKey: "actionHotkey") ?? "control+option+s") ?? .defaultAction }
        set { defaults.set(newValue.rawValue, forKey: "actionHotkey") }
    }

    var panelHotkey: HotkeyDefinition {
        get { HotkeyDefinition(rawValue: defaults.string(forKey: "panelHotkey") ?? "control+option+w") ?? .defaultPanel }
        set { defaults.set(newValue.rawValue, forKey: "panelHotkey") }
    }

    var clipboardDockHotkey: HotkeyDefinition {
        get { HotkeyDefinition(rawValue: defaults.string(forKey: "clipboardDockHotkey") ?? "command+d") ?? .defaultClipboardDock }
        set { defaults.set(newValue.rawValue, forKey: "clipboardDockHotkey") }
    }

    var saveDirectory: URL {
        get {
            if let value = defaults.string(forKey: "saveDirectory") {
                return URL(fileURLWithPath: value, isDirectory: true)
            }
            return defaultSaveDirectory
        }
        set { defaults.set(newValue.path, forKey: "saveDirectory") }
    }

    var colorFormat: String {
        get { defaults.string(forKey: "colorFormat") ?? "HEX" }
        set { defaults.set(newValue, forKey: "colorFormat") }
    }

    var middleClickEnabled: Bool {
        get {
            if defaults.object(forKey: "middleClickEnabled") == nil {
                return true
            }
            return defaults.bool(forKey: "middleClickEnabled")
        }
        set { defaults.set(newValue, forKey: "middleClickEnabled") }
    }

    var clipboardHistoryEnabled: Bool {
        get {
            if defaults.object(forKey: "clipboardHistoryEnabled") == nil {
                return true
            }
            return defaults.bool(forKey: "clipboardHistoryEnabled")
        }
        set { defaults.set(newValue, forKey: "clipboardHistoryEnabled") }
    }

    func buildFileURL() throws -> URL {
        try FileManager.default.createDirectory(at: saveDirectory, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = "capture-\(formatter.string(from: Date())).png"
        return saveDirectory.appendingPathComponent(name)
    }
}
