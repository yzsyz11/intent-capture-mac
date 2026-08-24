import Foundation
import Security

/// 区域翻译的引擎类型。上层按此选择具体 `Translator` 实现。
enum TranslationEngine: String, CaseIterable {
    case deepseek
    case apple

    var title: String {
        switch self {
        case .deepseek: return "DeepSeek"
        case .apple: return "Apple 原生"
        }
    }

    /// 引擎切换开关上显示的模式名。DeepSeek 归入更可扩展的「自定义大模型」。
    var toggleTitle: String {
        switch self {
        case .apple: return "Apple 原生"
        case .deepseek: return "自定义大模型"
        }
    }

    /// 开关上模式名旁的头像（SF Symbol）。DeepSeek 暂用占位符号。
    var avatarSymbol: String {
        switch self {
        case .apple: return "apple.logo"
        case .deepseek: return "sparkles"
        }
    }

    var subtitle: String {
        switch self {
        case .apple: return "免费 · 离线 · 需 macOS 15+"
        case .deepseek: return "接入你的大模型 API Key"
        }
    }

    /// 是否需要填写 API Key。
    var needsAPIKey: Bool { self == .deepseek }
}

/// 把非 Sendable 值（如 NSImage）安全地带过 Task 边界；调用方须保证只在同一线程（主线程）使用。
struct UncheckedSendableBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

/// OCR 出的一行文字及其在选区内的归一化位置（Vision 坐标：左下原点，[0,1]）。
struct OCRLine {
    let text: String
    /// 归一化 boundingBox，origin 左下。覆盖层按选区尺寸换算成视图坐标。
    let box: CGRect
}

/// 翻译引擎抽象：输入若干行原文，返回一一对应的译文行。
protocol Translator {
    var isAvailable: Bool { get }
    func translate(_ lines: [String], to target: String) async throws -> [String]
}

enum TranslationError: LocalizedError {
    case missingAPIKey
    case badResponse(String)
    case engineUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "未配置 DeepSeek API Key，请到设置 → 翻译中填写"
        case .badResponse(let detail): return "翻译服务返回异常：\(detail)"
        case .engineUnavailable(let detail): return detail
        }
    }
}

// MARK: - DeepSeek（OpenAI 兼容 /chat/completions，仅用 URLSession，零依赖）

final class DeepSeekTranslator: Translator {
    private let apiKey: String
    private let endpoint = URL(string: "https://api.deepseek.com/chat/completions")!

    init(apiKey: String) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isAvailable: Bool { !apiKey.isEmpty }

    func translate(_ lines: [String], to target: String) async throws -> [String] {
        guard !apiKey.isEmpty else { throw TranslationError.missingAPIKey }
        guard !lines.isEmpty else { return [] }

        // 以 JSON 数组承载原文，要求模型返回等长对象 {"lines": [...]}，保证逐行对齐。
        let payloadLines = try String(data: JSONEncoder().encode(lines), encoding: .utf8) ?? "[]"
        let system = """
        你是一个翻译引擎。把用户提供的 JSON 字符串数组中的每一项翻译成\(target)。
        只返回一个 JSON 对象，形如 {"lines": ["译文1", "译文2", ...]}，
        数组长度与顺序必须与输入完全一致；只输出译文本身，不要解释、不要加引号以外的多余字符。
        若某项已是目标语言或无需翻译，原样返回该项。
        """

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "model": "deepseek-chat",
            "temperature": 0,
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": payloadLines]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TranslationError.badResponse("无 HTTP 响应")
        }
        guard http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw TranslationError.badResponse("HTTP \(http.statusCode) \(msg.prefix(200))")
        }

        let content = try Self.extractContent(from: data)
        return Self.parseLines(from: content, expected: lines.count)
    }

    /// 取出 choices[0].message.content。
    private static func extractContent(from data: Data) throws -> String {
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = root["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            throw TranslationError.badResponse("无法解析 choices.message.content")
        }
        return content
    }

    /// 从模型返回的 content 里解析出译文行；解析失败时回退按换行切分。
    private static func parseLines(from content: String, expected: Int) -> [String] {
        let cleaned = content
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let data = cleaned.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let arr = obj["lines"] as? [String] {
            return Self.reconcile(arr, expected: expected)
        }
        if let data = cleaned.data(using: .utf8),
           let arr = try? JSONSerialization.jsonObject(with: data) as? [String] {
            return Self.reconcile(arr, expected: expected)
        }
        // 回退：按换行切分。
        let fallback = cleaned.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return Self.reconcile(fallback, expected: expected)
    }

    /// 补齐/截断到期望行数，避免覆盖层错位。
    private static func reconcile(_ arr: [String], expected: Int) -> [String] {
        if arr.count == expected { return arr }
        if arr.count > expected { return Array(arr.prefix(expected)) }
        return arr + Array(repeating: "", count: expected - arr.count)
    }
}

// MARK: - Keychain

/// 极简 Keychain 读写（generic password），用于存 API Key。
enum KeychainStore {
    private static let service = "local.intentcapture.mac"

    static func write(_ value: String, account: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var attrs = query
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attrs as CFDictionary, nil)
    }

    static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
