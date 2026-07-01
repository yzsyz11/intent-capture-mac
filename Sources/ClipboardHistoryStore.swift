import AppKit
import Foundation

enum ClipboardHistoryKind: String, Codable {
    case text
    case image
    case color
    case link
}

struct ClipboardHistoryItem: Codable, Equatable {
    let id: String
    let kind: ClipboardHistoryKind
    let createdAt: Date
    let preview: String
    let detail: String
    let fingerprint: String
    let imageFilename: String?
    let imageWidth: Int?
    let imageHeight: Int?
}

final class ClipboardHistoryStore {
    static let shared = ClipboardHistoryStore()

    private let maxItems = 50
    private let fileManager = FileManager.default
    private let rootDirectory: URL
    private let imagesDirectory: URL
    private let indexURL: URL
    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount

    private(set) var items: [ClipboardHistoryItem] = []
    var onChange: (([ClipboardHistoryItem]) -> Void)?

    init(rootDirectory: URL? = nil) {
        let base = rootDirectory ?? Self.defaultRootDirectory()
        self.rootDirectory = base
        self.imagesDirectory = base.appendingPathComponent("Images", isDirectory: true)
        self.indexURL = base.appendingPathComponent("index.json")
        load()
    }

    func start() {
        stop()
        lastChangeCount = NSPasteboard.general.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 0.55, repeats: true) { [weak self] _ in
            self?.pollPasteboard()
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func pollPasteboard() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        guard let item = makeItem(from: pasteboard) else { return }
        add(item)
    }

    func clear() {
        items.removeAll()
        try? fileManager.removeItem(at: imagesDirectory)
        save()
        onChange?(items)
    }

    func delete(_ item: ClipboardHistoryItem) {
        items.removeAll { $0.id == item.id }
        if let filename = item.imageFilename {
            try? fileManager.removeItem(at: imagesDirectory.appendingPathComponent(filename))
        }
        save()
        onChange?(items)
    }

    func update(_ item: ClipboardHistoryItem, newText: String) {
        guard item.kind != .image, let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let kind = Self.kind(for: trimmed)
        let detail: String
        switch kind {
        case .color: detail = "颜色"
        case .link: detail = "链接"
        default: detail = "文字"
        }
        items[index] = ClipboardHistoryItem(
            id: item.id,
            kind: kind,
            createdAt: item.createdAt,
            preview: trimmed,
            detail: detail,
            fingerprint: "\(kind.rawValue):\(trimmed)",
            imageFilename: nil,
            imageWidth: nil,
            imageHeight: nil
        )
        save()
        onChange?(items)
    }

    func restore(_ item: ClipboardHistoryItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        if let image = image(for: item) {
            pasteboard.writeObjects([image])
        } else {
            pasteboard.setString(item.preview, forType: .string)
        }
        lastChangeCount = pasteboard.changeCount
    }

    func image(for item: ClipboardHistoryItem) -> NSImage? {
        guard let filename = item.imageFilename else { return nil }
        return NSImage(contentsOf: imagesDirectory.appendingPathComponent(filename))
    }

    private func add(_ item: ClipboardHistoryItem) {
        items.removeAll { $0.fingerprint == item.fingerprint }
        items.insert(item, at: 0)
        if items.count > maxItems {
            let removed = items.suffix(from: maxItems)
            removed.compactMap(\.imageFilename).forEach { filename in
                try? fileManager.removeItem(at: imagesDirectory.appendingPathComponent(filename))
            }
            items = Array(items.prefix(maxItems))
        }
        save()
        onChange?(items)
    }

    private func makeItem(from pasteboard: NSPasteboard) -> ClipboardHistoryItem? {
        if let string = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !string.isEmpty {
            let kind = Self.kind(for: string)
            let preview = string
            let detail: String
            switch kind {
            case .color:
                detail = "颜色"
            case .link:
                detail = "链接"
            default:
                detail = "文字"
            }
            return ClipboardHistoryItem(
                id: UUID().uuidString,
                kind: kind,
                createdAt: Date(),
                preview: preview,
                detail: detail,
                fingerprint: "\(kind.rawValue):\(preview)",
                imageFilename: nil,
                imageWidth: nil,
                imageHeight: nil
            )
        }

        guard let image = NSImage(pasteboard: pasteboard),
              let pngData = image.clipboardPNGData else {
            return nil
        }

        do {
            try fileManager.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
            let filename = "\(UUID().uuidString).png"
            try pngData.write(to: imagesDirectory.appendingPathComponent(filename))
            let pixelSize = image.pixelSize
            return ClipboardHistoryItem(
                id: UUID().uuidString,
                kind: .image,
                createdAt: Date(),
                preview: "图片",
                detail: "\(Int(pixelSize.width))x\(Int(pixelSize.height))",
                fingerprint: "image:\(pngData.count):\(Int(pixelSize.width))x\(Int(pixelSize.height))",
                imageFilename: filename,
                imageWidth: Int(pixelSize.width),
                imageHeight: Int(pixelSize.height)
            )
        } catch {
            return nil
        }
    }

    private func load() {
        do {
            let data = try Data(contentsOf: indexURL)
            items = try JSONDecoder().decode([ClipboardHistoryItem].self, from: data)
        } catch {
            items = []
        }
    }

    private func save() {
        do {
            try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(items)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            Toast.show("剪贴板历史保存失败：\(error.localizedDescription)")
        }
    }

    private static func kind(for string: String) -> ClipboardHistoryKind {
        if isColor(string) { return .color }
        if isLink(string) { return .link }
        return .text
    }

    private static func isColor(_ string: String) -> Bool {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let hex = #"^#([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$"#
        let rgb = #"^rgb\(\s*\d{1,3}\s*,\s*\d{1,3}\s*,\s*\d{1,3}\s*\)$"#
        return trimmed.range(of: hex, options: .regularExpression) != nil
            || trimmed.range(of: rgb, options: .regularExpression) != nil
    }

    private static func isLink(_ string: String) -> Bool {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return false
        }
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        let matches = detector.matches(in: string, options: [], range: range)
        return matches.contains { $0.range.location == 0 && $0.range.length == range.length }
    }

    private static func defaultRootDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return appSupport.appendingPathComponent("IntentCapture/ClipboardHistory", isDirectory: true)
    }
}

private extension NSImage {
    var clipboardPNGData: Data? {
        guard let tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }

    var pixelSize: CGSize {
        if let rep = representations.first {
            return CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        }
        return size
    }
}
