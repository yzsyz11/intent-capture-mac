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
    let isPinned: Bool
    let pinnedAt: Date?

    init(
        id: String,
        kind: ClipboardHistoryKind,
        createdAt: Date,
        preview: String,
        detail: String,
        fingerprint: String,
        imageFilename: String?,
        imageWidth: Int?,
        imageHeight: Int?,
        isPinned: Bool = false,
        pinnedAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.createdAt = createdAt
        self.preview = preview
        self.detail = detail
        self.fingerprint = fingerprint
        self.imageFilename = imageFilename
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.isPinned = isPinned
        self.pinnedAt = pinnedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case createdAt
        case preview
        case detail
        case fingerprint
        case imageFilename
        case imageWidth
        case imageHeight
        case isPinned
        case pinnedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        kind = try container.decode(ClipboardHistoryKind.self, forKey: .kind)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        preview = try container.decode(String.self, forKey: .preview)
        detail = try container.decode(String.self, forKey: .detail)
        fingerprint = try container.decode(String.self, forKey: .fingerprint)
        imageFilename = try container.decodeIfPresent(String.self, forKey: .imageFilename)
        imageWidth = try container.decodeIfPresent(Int.self, forKey: .imageWidth)
        imageHeight = try container.decodeIfPresent(Int.self, forKey: .imageHeight)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        pinnedAt = try container.decodeIfPresent(Date.self, forKey: .pinnedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(preview, forKey: .preview)
        try container.encode(detail, forKey: .detail)
        try container.encode(fingerprint, forKey: .fingerprint)
        try container.encodeIfPresent(imageFilename, forKey: .imageFilename)
        try container.encodeIfPresent(imageWidth, forKey: .imageWidth)
        try container.encodeIfPresent(imageHeight, forKey: .imageHeight)
        try container.encode(isPinned, forKey: .isPinned)
        try container.encodeIfPresent(pinnedAt, forKey: .pinnedAt)
    }

    func cardPreviewText(maxCharacters: Int = 240) -> String {
        guard preview.count > maxCharacters else { return preview }
        return String(preview.prefix(maxCharacters)) + "…"
    }
}

final class ClipboardHistoryStore {
    static let shared = ClipboardHistoryStore()

    private let maxItems = 50
    private let fileManager = FileManager.default
    private let rootDirectory: URL
    private let imagesDirectory: URL
    private let indexURL: URL
    private let imageCache = NSCache<NSString, NSImage>()
    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount
    // 所有磁盘 IO（index.json 与 PNG 写盘）都排到这条串行后台队列，主线程只维护内存 items。
    private let ioQueue = DispatchQueue(label: "com.intentcapture.clipboardhistory.io", qos: .utility)
    // 连续操作时的写盘去抖：只保留最后一次，300ms 内合并。
    private var pendingSave: DispatchWorkItem?
    private let saveDebounce: TimeInterval = 0.3

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
        let removed = items.filter { !$0.isPinned }
        removed.compactMap(\.imageFilename).forEach { filename in
            try? fileManager.removeItem(at: imagesDirectory.appendingPathComponent(filename))
            imageCache.removeObject(forKey: filename as NSString)
        }
        items.removeAll { !$0.isPinned }
        save()
        onChange?(items)
    }

    func delete(_ item: ClipboardHistoryItem) {
        items.removeAll { $0.id == item.id }
        if let filename = item.imageFilename {
            try? fileManager.removeItem(at: imagesDirectory.appendingPathComponent(filename))
            imageCache.removeObject(forKey: filename as NSString)
        }
        save()
        onChange?(items)
    }

    func delete(ids: Set<String>) {
        guard !ids.isEmpty else { return }
        let removed = items.filter { ids.contains($0.id) }
        guard !removed.isEmpty else { return }
        items.removeAll { ids.contains($0.id) }
        removed.compactMap(\.imageFilename).forEach { filename in
            try? fileManager.removeItem(at: imagesDirectory.appendingPathComponent(filename))
            imageCache.removeObject(forKey: filename as NSString)
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
            imageHeight: nil,
            isPinned: item.isPinned,
            pinnedAt: item.pinnedAt
        )
        items = sortedPinnedFirst(items)
        save()
        onChange?(items)
    }

    func togglePinned(_ item: ClipboardHistoryItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let existing = items[index]
        items[index] = ClipboardHistoryItem(
            id: existing.id,
            kind: existing.kind,
            createdAt: existing.createdAt,
            preview: existing.preview,
            detail: existing.detail,
            fingerprint: existing.fingerprint,
            imageFilename: existing.imageFilename,
            imageWidth: existing.imageWidth,
            imageHeight: existing.imageHeight,
            isPinned: !existing.isPinned,
            pinnedAt: existing.isPinned ? nil : Date()
        )
        items = sortedPinnedFirst(items)
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
        let key = filename as NSString
        if let cached = imageCache.object(forKey: key) { return cached }
        guard let image = NSImage(contentsOf: imagesDirectory.appendingPathComponent(filename)) else { return nil }
        imageCache.setObject(image, forKey: key)
        return image
    }

    private func add(_ item: ClipboardHistoryItem) {
        let existingPinned = items.first { $0.fingerprint == item.fingerprint && $0.isPinned }
        let duplicateImages = items
            .filter { $0.fingerprint == item.fingerprint }
            .compactMap(\.imageFilename)
        items.removeAll { $0.fingerprint == item.fingerprint }
        duplicateImages
            .filter { $0 != item.imageFilename }
            .forEach { filename in
                try? fileManager.removeItem(at: imagesDirectory.appendingPathComponent(filename))
                imageCache.removeObject(forKey: filename as NSString)
            }
        items.insert(ClipboardHistoryItem(
            id: existingPinned?.id ?? item.id,
            kind: item.kind,
            createdAt: item.createdAt,
            preview: item.preview,
            detail: item.detail,
            fingerprint: item.fingerprint,
            imageFilename: item.imageFilename,
            imageWidth: item.imageWidth,
            imageHeight: item.imageHeight,
            isPinned: existingPinned?.isPinned ?? item.isPinned,
            pinnedAt: existingPinned?.pinnedAt ?? item.pinnedAt
        ), at: 0)
        items = sortedPinnedFirst(items)
        trimNormalItemsToCapacity()
        save()
        onChange?(items)
    }

    private func sortedPinnedFirst(_ records: [ClipboardHistoryItem]) -> [ClipboardHistoryItem] {
        let pinned = records.filter(\.isPinned).sorted {
            ($0.pinnedAt ?? .distantPast) > ($1.pinnedAt ?? .distantPast)
        }
        let normal = records.filter { !$0.isPinned }
        return pinned + normal
    }

    private func trimNormalItemsToCapacity() {
        let pinnedCount = items.filter(\.isPinned).count
        let normalCapacity = max(maxItems - pinnedCount, 0)
        var normalSeen = 0
        var trimmed: [ClipboardHistoryItem] = []
        var removed: [ClipboardHistoryItem] = []

        for item in items {
            if item.isPinned {
                trimmed.append(item)
            } else if normalSeen < normalCapacity {
                trimmed.append(item)
                normalSeen += 1
            } else {
                removed.append(item)
            }
        }

        removed.compactMap(\.imageFilename).forEach { filename in
            try? fileManager.removeItem(at: imagesDirectory.appendingPathComponent(filename))
            imageCache.removeObject(forKey: filename as NSString)
        }
        items = trimmed
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

        let filename = "\(UUID().uuidString).png"
        let pixelSize = image.pixelSize
        // 立即缓存，卡片渲染无需等磁盘；PNG 编码已在主线程完成（指纹需要字节数），实际写盘排到后台队列。
        imageCache.setObject(image, forKey: filename as NSString)
        writeImageAsync(pngData, filename: filename)
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
    }

    private func load() {
        do {
            let data = try Data(contentsOf: indexURL)
            items = try JSONDecoder().decode([ClipboardHistoryItem].self, from: data)
        } catch {
            items = []
        }
    }

    // 去抖 + 后台写盘：在主线程对 items 取值快照，取消上一次挂起的写盘，300ms 后到后台串行落盘。
    private func save() {
        pendingSave?.cancel()
        let snapshot = items
        let work = DispatchWorkItem { [weak self] in
            self?.writeIndex(snapshot)
        }
        pendingSave = work
        ioQueue.asyncAfter(deadline: .now() + saveDebounce, execute: work)
    }

    private func writeIndex(_ snapshot: [ClipboardHistoryItem]) {
        do {
            try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            DispatchQueue.main.async {
                Toast.show("剪贴板历史保存失败：\(error.localizedDescription)")
            }
        }
    }

    private func writeImageAsync(_ data: Data, filename: String) {
        ioQueue.async { [weak self] in
            guard let self else { return }
            do {
                try self.fileManager.createDirectory(at: self.imagesDirectory, withIntermediateDirectories: true)
                try data.write(to: self.imagesDirectory.appendingPathComponent(filename))
            } catch {
                DispatchQueue.main.async {
                    Toast.show("截图写入失败：\(error.localizedDescription)")
                }
            }
        }
    }

    /// 退出前强制同步刷盘，避免去抖窗口内的最后一次改动丢失。
    func flush() {
        pendingSave?.cancel()
        pendingSave = nil
        let snapshot = items
        ioQueue.sync { writeIndex(snapshot) }
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
