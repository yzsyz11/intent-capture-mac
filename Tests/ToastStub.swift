import AppKit

// 测试桩：签名需与 Sources/CaptureService.swift 的 Toast.show 对齐。
// FeedbackTone 真身在 Design.swift（依赖 AppSettings，不便进测试组），这里放一份最小同构定义，
// 仅供回归测试独立编译使用；不进入主构建（SOURCES 不含本文件），故不会与真身冲突。
enum FeedbackTone { case success, info, warning, danger, delete }

enum Toast {
    static func show(_ message: String, tone: FeedbackTone = .info, image: NSImage? = nil) {}
}
