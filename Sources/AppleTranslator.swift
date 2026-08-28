import AppKit
import SwiftUI
#if canImport(Translation)
import Translation
#endif

/// Apple 原生翻译（macOS 15+）。`TranslationSession` 只能由 SwiftUI 的 `.translationTask`
/// 供给，故这里藏一个近乎不可见的 `NSHostingView` 承载会话，用 continuation 把结果桥回 AppKit。
@available(macOS 15.0, *)
final class AppleTranslator: Translator {
    var isAvailable: Bool { true }

    func translate(_ lines: [String], to target: String) async throws -> [String] {
        guard !lines.isEmpty else { return [] }
        let language = Self.language(for: target)
        TranslationDebugLog.log("Apple 翻译 target=\(target) 行数=\(lines.count)")
        let result = try await AppleTranslationBridge.shared.translate(lines, target: language)
        TranslationDebugLog.log("Apple 返回 \(result.count) 行")
        return result
    }

    /// 目标语言显示名 → `Locale.Language`。源语言交给系统自动检测。
    private static func language(for display: String) -> Locale.Language {
        switch display {
        case "中文（简体）": return Locale.Language(identifier: "zh-Hans")
        case "中文（繁体）": return Locale.Language(identifier: "zh-Hant")
        case "English": return Locale.Language(identifier: "en")
        case "日本語": return Locale.Language(identifier: "ja")
        case "한국어": return Locale.Language(identifier: "ko")
        default: return Locale.Language(identifier: "zh-Hans")
        }
    }
}

@available(macOS 15.0, *)
@MainActor
private final class AppleTranslationBridge {
    static let shared = AppleTranslationBridge()
    private var window: NSWindow?

    func translate(_ lines: [String], target: Locale.Language) async throws -> [String] {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[String], Error>) in
            var finished = false
            let finish: (Result<[String], Error>) -> Void = { [weak self] result in
                guard !finished else { return }
                finished = true
                self?.window?.orderOut(nil)
                self?.window = nil
                continuation.resume(with: result)
            }

            let root = AppleTranslationHostView(lines: lines, target: target, completion: finish)
            let hosting = NSHostingView(rootView: root)
            // 需在窗口层级里 `.translationTask` 才会触发；首用语言包下载的系统弹窗也需附着于此。
            let win = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 360, height: 120),
                               styleMask: [.titled], backing: .buffered, defer: false)
            win.contentView = hosting
            win.alphaValue = 0.02
            win.level = .floating
            win.orderFrontRegardless()
            self.window = win
        }
    }
}

@available(macOS 15.0, *)
private struct AppleTranslationHostView: View {
    let lines: [String]
    let target: Locale.Language
    let completion: (Result<[String], Error>) -> Void
    @State private var configuration: TranslationSession.Configuration?

    var body: some View {
        Color.clear
            .translationTask(configuration) { session in
                do {
                    let requests = lines.enumerated().map { pair in
                        TranslationSession.Request(sourceText: pair.element,
                                                   clientIdentifier: String(pair.offset))
                    }
                    let responses = try await session.translations(from: requests)
                    var byId: [Int: String] = [:]
                    for response in responses {
                        if let cid = response.clientIdentifier, let index = Int(cid) {
                            byId[index] = response.targetText
                        }
                    }
                    let ordered = (0..<lines.count).map { byId[$0] ?? "" }
                    completion(.success(ordered))
                } catch {
                    completion(.failure(error))
                }
            }
            .onAppear {
                configuration = TranslationSession.Configuration(source: nil, target: target)
            }
    }
}
