import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// 可靠重启：脱离进程的 helper 先等旧实例真正退出，再以新实例拉起。
///
/// 直接 `open` 常失败，是因为它会复用正在退出的旧实例、或旧进程尚未释放端口/tap。
/// `sleep 1` 等旧进程退干净，`open -n` 强制开新实例，兜住"屏幕录制授权后被系统杀进程"的情况。
enum AppRelauncher {
    static func relaunch() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", "sleep 1; open -n \"\(path)\""]
        try? task.run()
        NSApp.terminate(nil)
    }
}

/// 权限自愈：对症执行"清僵尸 + 重授"，并把用户带到对应系统设置页。
enum PermissionHealer {
    private static var bundleID: String {
        Bundle.main.bundleIdentifier ?? "local.intentcapture.mac"
    }

    /// `tccutil reset <service> <bundleID>`：清掉旧僵尸条目，免用户手动去系统设置删。
    /// 受管 / 沙盒环境可能失败 → 返回 false，调用方回退到"手动删条目"文案，不卡死。
    @discardableResult
    static func resetTCC(_ kind: PermissionKind) -> Bool {
        let task = Process()
        task.launchPath = "/usr/bin/tccutil"
        task.arguments = ["reset", kind.tccService, bundleID]
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// 打开对应权限的系统设置页。
    static func openSettings(_ kind: PermissionKind) {
        let anchor: String
        switch kind {
        case .accessibility: anchor = "Privacy_Accessibility"
        case .screenRecording: anchor = "Privacy_ScreenCapture"
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }

    /// 对症自愈：
    /// - `.stale`（僵尸）→ 先 `tccutil reset` 清旧条目，再拉授权。
    /// - `.notGranted` → 直接拉授权。
    /// - `.granted` → 无需操作。
    /// 返回是否已发起系统授权流程（用于 UI 决定是否进入轮询等待）。
    @discardableResult
    static func heal(_ kind: PermissionKind, state: PermissionState) -> Bool {
        guard state != .granted else { return false }
        if state == .stale {
            _ = resetTCC(kind)
        }
        switch kind {
        case .accessibility:
            // 拉系统授权弹窗；同时打开设置页兜底（reset 后弹窗有时不出现）。
            AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        case .screenRecording:
            CGRequestScreenCaptureAccess()
        }
        openSettings(kind)
        return true
    }
}

/// 权限轮询器：每 0.5s 检查一次两项权限，状态变化时回调；用于引导向导自动前进。
/// 窗口关闭 / 完成后务必 `stop()`，避免常驻耗电。
final class PermissionWatcher {
    private var timer: Timer?
    private var last: [PermissionKind: PermissionState] = [:]
    private let onChange: ([PermissionKind: PermissionState]) -> Void

    init(onChange: @escaping ([PermissionKind: PermissionState]) -> Void) {
        self.onChange = onChange
    }

    func start() {
        stop()
        emit()  // 立即回调一次当前状态
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let now = snapshot()
        if now != last { emit(now) }
    }

    private func emit(_ snapshotOverride: [PermissionKind: PermissionState]? = nil) {
        let now = snapshotOverride ?? snapshot()
        last = now
        onChange(now)
    }

    private func snapshot() -> [PermissionKind: PermissionState] {
        var result: [PermissionKind: PermissionState] = [:]
        for kind in PermissionKind.allCases {
            result[kind] = PermissionEvaluator.state(of: kind)
        }
        return result
    }

    deinit { stop() }
}
