import ApplicationServices
import CoreGraphics
import Foundation

/// 单项系统权限的三态。
///
/// 系统 API 只回答 true/false，但 false 有两种含义、修法相反：
/// - `.notGranted`：从没授过（或同一安装里被手动关掉）→ 直接拉授权弹窗 / 去打开开关。
/// - `.stale`：曾经授过、现在失效——多因换机、重装或签名身份变化留下 TCC 僵尸条目
///   → 需先 `tccutil reset` 清掉旧条目再重授（阶段三的一键自愈）。
///
/// 稳定签名（见 create-signing-identity.sh）让 `.stale` 日常基本不再发生，
/// 三态仍作为换机 / 证书重建时的兜底，并为升级引导提供"版本变了"的触发信号。
enum PermissionState {
    case granted
    case notGranted
    case stale
}

/// 需要引导开通的两项权限。
enum PermissionKind: CaseIterable {
    case accessibility     // 辅助功能：中键监听
    case screenRecording   // 屏幕录制：截图 / 取色 / OCR

    /// 当前是否已生效（唯一系统真值来源）。
    var isGranted: Bool {
        switch self {
        case .accessibility: return AXIsProcessTrusted()
        case .screenRecording: return CGPreflightScreenCaptureAccess()
        }
    }

    /// UserDefaults 键后缀。
    var storageKey: String {
        switch self {
        case .accessibility: return "accessibility"
        case .screenRecording: return "screenRecording"
        }
    }

    /// `tccutil reset <service>` 用的服务名（阶段三一键自愈使用）。
    var tccService: String {
        switch self {
        case .accessibility: return "Accessibility"
        case .screenRecording: return "ScreenCapture"
        }
    }

    /// 中文名，用于引导文案。
    var displayName: String {
        switch self {
        case .accessibility: return "辅助功能"
        case .screenRecording: return "屏幕录制"
        }
    }
}

/// 当前安装的构建身份签名：版本号 + 可执行文件修改时间。
/// 新版本覆盖安装后可执行文件 mtime 变化 → 签名变化，用于区分
/// "重装/重签导致的僵尸" 与 "同一安装内手动关权限"，也用于升级引导触发。
enum AppBuildSignature {
    static var current: String {
        let version = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        var stamp = "0"
        if let exec = Bundle.main.executableURL,
           let attrs = try? FileManager.default.attributesOfItem(atPath: exec.path),
           let date = attrs[.modificationDate] as? Date {
            stamp = String(Int(date.timeIntervalSince1970))
        }
        return "\(version)|\(stamp)"
    }
}

/// 三态判定。判为 `.granted` 时顺手记录历史与当前签名，供后续判定与升级触发使用。
enum PermissionEvaluator {
    /// 纯决策：与系统 / 存储解耦，便于单元测试。
    /// - 已生效 → granted
    /// - 从没授过 → notGranted
    /// - 曾授过：签名变了（重装/重签）→ stale（僵尸）；签名没变（手动关）→ notGranted
    static func decide(isGranted: Bool, hasEverGranted: Bool, signatureMatches: Bool) -> PermissionState {
        if isGranted { return .granted }
        guard hasEverGranted else { return .notGranted }
        return signatureMatches ? .notGranted : .stale
    }

    static func state(of kind: PermissionKind, settings: AppSettings = .shared) -> PermissionState {
        let signature = AppBuildSignature.current
        let granted = kind.isGranted
        if granted {
            settings.markGranted(kind, signature: signature)
        }
        return decide(
            isGranted: granted,
            hasEverGranted: settings.hasEverGranted(kind),
            signatureMatches: settings.lastGrantedSignature(kind) == signature
        )
    }
}
