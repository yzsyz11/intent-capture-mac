import AppKit
import Foundation

final class AppSettings {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard
    private let defaultSaveDirectory = URL(fileURLWithPath: "/Users/a1/Downloads/截图", isDirectory: true)

    private init() {
        // 一次性清理旧的 Keychain 项：ad-hoc 每次重签名身份都变，旧 key 会让系统在读取时反复弹钥匙串授权。
        KeychainStore.delete(account: "deepseek.apiKey")
    }

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

    /// 是否已完成首次启动引导；首启弹主页引导，之后常驻菜单栏静默，不再主动弹窗。
    var hasLaunchedBefore: Bool {
        get { defaults.bool(forKey: "hasLaunchedBefore") }
        set { defaults.set(newValue, forKey: "hasLaunchedBefore") }
    }

    /// 全局主题强调色（十六进制），应用于侧边栏高亮、按钮描边与中键轮盘。
    static let defaultAccentHex = "#2EA6C7"

    var accentHex: String {
        get { defaults.string(forKey: "accentColor") ?? Self.defaultAccentHex }
        set { defaults.set(newValue, forKey: "accentColor") }
    }

    var accentColor: NSColor {
        get { NSColor(hexString: accentHex) ?? NSColor(hexString: Self.defaultAccentHex)! }
        set { accentHex = newValue.hexString }
    }

    // MARK: - 区域翻译

    /// 翻译引擎：`deepseek`（在线，需 key）/ `apple`（原生，macOS 15+，即将支持）。默认 DeepSeek。
    var translationEngine: TranslationEngine {
        get { TranslationEngine(rawValue: defaults.string(forKey: "translationEngine") ?? "") ?? .deepseek }
        set { defaults.set(newValue.rawValue, forKey: "translationEngine") }
    }

    /// 目标语言（直接作为提示词里的语言名，默认简体中文）。
    var translationTargetLanguage: String {
        get { defaults.string(forKey: "translationTargetLanguage") ?? "中文（简体）" }
        set { defaults.set(newValue, forKey: "translationTargetLanguage") }
    }

    /// DeepSeek API Key。改存 UserDefaults（本地明文）：Keychain 在 ad-hoc 重签后会反复弹授权，个人工具下不值当。
    var deepSeekAPIKey: String {
        get { defaults.string(forKey: "deepSeekAPIKey") ?? "" }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                defaults.removeObject(forKey: "deepSeekAPIKey")
            } else {
                defaults.set(trimmed, forKey: "deepSeekAPIKey")
            }
        }
    }

    /// 翻译调试日志开关：开启后把请求/返回/错误写进日志文件，便于排查错译漏译。
    var translationDebugLogEnabled: Bool {
        get { defaults.bool(forKey: "translationDebugLogEnabled") }
        set { defaults.set(newValue, forKey: "translationDebugLogEnabled") }
    }

    func buildFileURL() throws -> URL {
        try FileManager.default.createDirectory(at: saveDirectory, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = "capture-\(formatter.string(from: Date())).png"
        return saveDirectory.appendingPathComponent(name)
    }
}

extension NSColor {
    /// 从 "#RRGGBB" 生成 sRGB 颜色；便于主题色在存储与选中比较时无损往返。
    convenience init?(hexString: String) {
        let trimmed = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        let hex = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard hex.count == 6, let value = Int(hex, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((value >> 16) & 0xff) / 255,
                  green: CGFloat((value >> 8) & 0xff) / 255,
                  blue: CGFloat(value & 0xff) / 255,
                  alpha: 1)
    }

    var hexString: String {
        guard let rgb = usingColorSpace(.sRGB) else { return AppSettings.defaultAccentHex }
        let r = Int(round(rgb.redComponent * 255))
        let g = Int(round(rgb.greenComponent * 255))
        let b = Int(round(rgb.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
