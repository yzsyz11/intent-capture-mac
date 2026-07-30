import Foundation

private enum TestFailure: Error {
    case assertion(String)
}

@main
struct ClipboardCardPreviewTests {
    static func main() throws {
        let fullText = String(repeating: "长文本内容", count: 1_000)
        let item = ClipboardHistoryItem(
            id: "long-text",
            kind: .text,
            createdAt: Date(timeIntervalSince1970: 0),
            preview: fullText,
            detail: "文字",
            fingerprint: "text:long-text",
            imageFilename: nil,
            imageWidth: nil,
            imageHeight: nil
        )

        let cardText = item.cardPreviewText(maxCharacters: 240)

        guard cardText.count <= 241 else {
            throw TestFailure.assertion("卡片摘要不应排版超过 240 个正文字符和一个省略号")
        }
        guard cardText.hasSuffix("…") else {
            throw TestFailure.assertion("被截断的卡片摘要应以省略号结尾")
        }
        guard item.preview == fullText else {
            throw TestFailure.assertion("卡片摘要不能修改剪贴板中保存的完整内容")
        }

        print("clipboard card preview tests passed.")
    }
}
