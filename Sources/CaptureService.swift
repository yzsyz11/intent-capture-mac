import AppKit
import CoreGraphics
import Foundation
import Vision

final class CaptureService {
    private let settings = AppSettings.shared
    private var activeSelectionWindow: RegionSelectionWindow?
    private var activeTranslationOverlay: TranslationOverlayWindow?

    func perform(_ action: CaptureAction) {
        guard activeSelectionWindow == nil else { return }
        guard ensureScreenCaptureAccess() else { return }

        switch action {
        case .pickColor:
            pickColor()
        default:
            Toast.show("拖拽选择截图区域，按 Esc 取消")
            selectRegion { [weak self] rect in
                self?.handle(action, rect: rect)
            }
        }
    }

    private func handle(_ action: CaptureAction, rect: CGRect) {
        guard let image = capture(rect: rect) else {
            Toast.show("截图失败，请检查屏幕录制权限")
            return
        }

        switch action {
        case .screenshotCopy:
            copy(image)
            Toast.show("截图已复制，未保存文件", image: image)
        case .screenshotSave:
            save(image, copyAfterSave: false)
        case .screenshotSaveAndCopy:
            save(image, copyAfterSave: true)
        case .ocrCopy:
            recognize(image)
        case .translate:
            translate(rect: rect, image: image)
        case .pickColor:
            break
        }
    }

    private func selectRegion(_ completion: @escaping (CGRect) -> Void) {
        let selector = RegionSelectionWindow(screen: Self.currentMouseScreen(), mode: .region)
        activeSelectionWindow = selector
        selector.onRegion = { [weak self] rect in
            guard let self else { return }
            let window = self.activeSelectionWindow
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                completion(rect)
                self.activeSelectionWindow = nil
                _ = window
            }
        }
        selector.onCancel = { [weak self] in
            self?.activeSelectionWindow = nil
            Toast.show("已取消截图")
        }
        selector.show()
    }

    private func pickColor() {
        Toast.show("点击一个像素复制颜色，按 Esc 取消")
        let screen = Self.currentMouseScreen()
        let bg = CGWindowListCreateImage(Self.appKitRectToQuartz(screen.frame),
                                         [.optionOnScreenOnly], kCGNullWindowID, [.bestResolution])
        let selector = RegionSelectionWindow(screen: screen, mode: .point, backgroundCapture: bg)
        activeSelectionWindow = selector
        selector.onPoint = { [weak self] point in
            guard let strongSelf = self else { return }
            let window = strongSelf.activeSelectionWindow
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                defer {
                    strongSelf.activeSelectionWindow = nil
                    _ = window
                }
                guard let color = strongSelf.sampleColor(at: point) else {
                    Toast.show("取色失败")
                    return
                }
                let value = strongSelf.format(color)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(value, forType: .string)
                Toast.show("已复制 \(value)")
            }
        }
        selector.onCancel = { [weak self] in
            self?.activeSelectionWindow = nil
            Toast.show("已取消取色")
        }
        selector.show()
    }

    private func capture(rect: CGRect) -> NSImage? {
        let quartzRect = Self.appKitRectToQuartz(rect)
        guard let cgImage = CGWindowListCreateImage(quartzRect, [.optionOnScreenOnly], kCGNullWindowID, [.bestResolution]) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: rect.size)
    }

    private func copy(_ image: NSImage) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
    }

    private func save(_ image: NSImage, copyAfterSave: Bool) {
        do {
            let url = try settings.buildFileURL()
            guard let data = image.pngData else {
                Toast.show("保存失败：无法编码 PNG")
                return
            }
            try data.write(to: url)
            if copyAfterSave {
                copy(image)
                Toast.show("已保存并复制：\(url.lastPathComponent)", image: image)
            } else {
                Toast.show("已保存：\(url.lastPathComponent)", image: image)
            }
        } catch {
            Toast.show("保存失败：\(error.localizedDescription)")
        }
    }

    private func recognize(_ image: NSImage) {
        recognizeLines(image) { lines in
            let text = lines.map(\.text).joined(separator: "\n")
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                Toast.show("未识别到文字")
                return
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            let preview = lines.first(where: { !$0.text.isEmpty })?.text ?? text
            let truncated = preview.count > 44 ? String(preview.prefix(44)) + "…" : preview
            Toast.show("OCR 已复制：\(truncated)")
        }
    }

    /// 识别文字并保留每行归一化位置（Vision 坐标，左下原点）；`completion` 在主线程回调。
    private func recognizeLines(_ image: NSImage, completion: @escaping ([OCRLine]) -> Void) {
        guard let cgImage = image.ocrPreparedCGImage else {
            DispatchQueue.main.async { Toast.show("OCR 失败") }
            return
        }

        let request = VNRecognizeTextRequest { request, error in
            if let error = error {
                DispatchQueue.main.async { Toast.show("OCR 失败：\(error.localizedDescription)") }
                return
            }
            let lines = (request.results as? [VNRecognizedTextObservation])?
                .compactMap { obs -> OCRLine? in
                    guard let text = obs.topCandidates(1).first?.string, !text.isEmpty else { return nil }
                    return OCRLine(text: text, box: obs.boundingBox)
                } ?? []
            DispatchQueue.main.async { completion(lines) }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
        if #available(macOS 13.0, *) {
            request.automaticallyDetectsLanguage = true
        }

        DispatchQueue.global(qos: .userInitiated).async {
            try? VNImageRequestHandler(cgImage: cgImage).perform([request])
        }
    }

    private func translate(rect: CGRect, image: NSImage) {
        let settings = self.settings
        let translator: Translator
        switch settings.translationEngine {
        case .deepseek:
            let deepseek = DeepSeekTranslator(apiKey: settings.deepSeekAPIKey)
            guard deepseek.isAvailable else {
                Toast.show("未配置 DeepSeek API Key，请到设置 → 翻译中填写")
                return
            }
            translator = deepseek
        case .apple:
            if #available(macOS 15.0, *) {
                translator = AppleTranslator()
            } else {
                Toast.show("Apple 原生翻译需要 macOS 15 或更新版本，请改用自定义大模型")
                return
            }
        }

        recognizeLines(image) { lines in
            let sources = lines.map(\.text)
            guard !sources.isEmpty else {
                Toast.show("未识别到文字")
                return
            }
            Toast.show("翻译中…")
            let target = settings.translationTargetLanguage
            let boxes = lines.map(\.box)
            // NSImage 非 Sendable，但只在主线程使用；装箱后跨 Task 边界。
            let bg = UncheckedSendableBox(image)
            Task {
                do {
                    let translations = try await translator.translate(sources, to: target)
                    let translatedLines = zip(boxes, translations).map { OCRLine(text: $1, box: $0) }
                    await MainActor.run {
                        self.showTranslationOverlay(rect: rect, background: bg.value, lines: translatedLines)
                    }
                } catch {
                    await MainActor.run {
                        Toast.show("翻译失败：\(error.localizedDescription)")
                    }
                }
            }
        }
    }

    private func showTranslationOverlay(rect: CGRect, background: NSImage, lines: [OCRLine]) {
        let overlay = TranslationOverlayWindow(regionRect: rect, background: background, lines: lines)
        activeTranslationOverlay = overlay
        overlay.show()
    }

    private func sampleColor(at point: CGPoint) -> NSColor? {
        let quartzPoint = Self.appKitPointToQuartz(point)
        let rect = CGRect(x: quartzPoint.x, y: quartzPoint.y, width: 1, height: 1)
        guard let cgImage = CGWindowListCreateImage(rect, [.optionOnScreenOnly], kCGNullWindowID, [.bestResolution]) else {
            return nil
        }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        return bitmap.colorAt(x: 0, y: 0)
    }

    private func ensureScreenCaptureAccess() -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }

        CGRequestScreenCaptureAccess()
        Toast.show("屏幕录制权限未对当前 App 生效。请开启权限后退出并重新打开 Intent Capture。")
        openScreenRecordingSettings()
        return false
    }

    private func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    private func format(_ color: NSColor) -> String {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        let r = Int(round(rgb.redComponent * 255))
        let g = Int(round(rgb.greenComponent * 255))
        let b = Int(round(rgb.blueComponent * 255))
        if settings.colorFormat == "RGB" {
            return "rgb(\(r), \(g), \(b))"
        }
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    private static func appKitRectToQuartz(_ rect: CGRect) -> CGRect {
        let top = NSScreen.screens.map { $0.frame.maxY }.max() ?? rect.maxY
        return CGRect(x: rect.minX, y: top - rect.maxY, width: rect.width, height: rect.height)
    }

    private static func appKitPointToQuartz(_ point: CGPoint) -> CGPoint {
        let top = NSScreen.screens.map { $0.frame.maxY }.max() ?? point.y
        return CGPoint(x: point.x, y: top - point.y)
    }

    private static func currentMouseScreen() -> NSScreen {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
            ?? {
                fatalError("Intent Capture requires at least one display")
            }()
    }
}

private extension NSImage {
    var pngData: Data? {
        guard let tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }

    var ocrPreparedCGImage: CGImage? {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return cgImage }

        let targetWidth = max(width, 1600)
        guard targetWidth > width else { return cgImage }

        let scale = CGFloat(targetWidth) / CGFloat(width)
        let targetHeight = Int(CGFloat(height) * scale)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return cgImage
        }
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        return context.makeImage() ?? cgImage
    }
}

final class ToastWindow: NSPanel {
    init(message: String, image: NSImage? = nil, onPreview: (() -> Void)? = nil) {
        let hasImage = image != nil
        let size = CGSize(width: 420, height: hasImage ? 88 : 56)
        let screen = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
        let origin = CGPoint(x: screen.midX - size.width / 2, y: screen.maxY - size.height - 60)
        super.init(
            contentRect: CGRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        isReleasedWhenClosed = false
        level = .mainMenu
        hasShadow = true
        ignoresMouseEvents = onPreview == nil
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let view = ToastView(message: message, image: image)
        view.onPreview = onPreview
        contentView = view
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class ToastView: NSView {
    enum Tone {
        case success
        case warning
        case failure
        case info

        var color: NSColor {
            switch self {
            case .success: return .systemGreen
            case .warning: return .systemOrange
            case .failure: return .systemRed
            case .info: return .systemBlue
            }
        }

        var symbolName: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .failure: return "xmark.circle.fill"
            case .info: return "info.circle.fill"
            }
        }
    }

    private let content: ToastContentView
    var onPreview: (() -> Void)? {
        didSet { updateTrackingAreas() }
    }

    init(message: String, image: NSImage? = nil) {
        let tone = Self.tone(for: message)
        let h: CGFloat = image != nil ? 88 : 56
        content = ToastContentView(message: message, image: image, tone: tone,
                                   frame: CGRect(x: 0, y: 0, width: 420, height: h))
        super.init(frame: CGRect(x: 0, y: 0, width: 420, height: h))
        wantsLayer = true

        // 与剪贴板反馈胶囊统一的毛玻璃底 + 色调描边。
        let blur = NSVisualEffectView(frame: bounds)
        blur.autoresizingMask = [.width, .height]
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 16
        blur.layer?.masksToBounds = true
        blur.layer?.borderWidth = 1
        blur.layer?.borderColor = tone.color.withAlphaComponent(0.5).cgColor
        addSubview(blur)

        content.autoresizingMask = [.width, .height]
        addSubview(content)

        alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            self.animator().alphaValue = 1
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        if onPreview != nil {
            addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways], owner: self))
        }
    }

    override func resetCursorRects() {
        if onPreview != nil, !content.thumbRect.isEmpty {
            addCursorRect(content.thumbRect, cursor: .pointingHand)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        if content.thumbRect.contains(pt) {
            onPreview?()
        }
    }

    private static func tone(for message: String) -> Tone {
        if message.contains("失败") || message.contains("不可用") || message.contains("未生效") || message.contains("未授权") {
            return .failure
        }
        if message.contains("权限") || message.contains("取消") || message.contains("请") {
            return .warning
        }
        if message.contains("已") || message.contains("成功") {
            return .success
        }
        return .info
    }
}

private final class ToastContentView: NSView {
    let thumbRect: CGRect

    init(message: String, image: NSImage?, tone: ToastView.Tone, frame: NSRect) {
        let hasImage = image != nil
        let thumbW: CGFloat = 96, thumbH: CGFloat = 68
        let thumbX = frame.width - thumbW - 14
        thumbRect = hasImage
            ? CGRect(x: thumbX, y: (frame.height - thumbH) / 2, width: thumbW, height: thumbH)
            : .zero
        super.init(frame: frame)
        wantsLayer = true

        // 色调图标（SF Symbol）
        let iconSize: CGFloat = 20
        let icon = NSImageView(frame: CGRect(x: 16, y: (frame.height - iconSize) / 2, width: iconSize, height: iconSize))
        icon.image = NSImage(systemSymbolName: tone.symbolName, accessibilityDescription: nil)
        icon.contentTintColor = tone.color
        icon.imageScaling = .scaleProportionallyUpOrDown
        addSubview(icon)

        // 文本（OCR 前缀 + 蓝色内容特例）
        let textRight = hasImage ? thumbX - 10 : frame.width - 14
        let label = NSTextField(labelWithString: message)
        label.backgroundColor = .clear
        label.isBordered = false
        label.lineBreakMode = .byTruncatingTail
        label.cell?.usesSingleLineMode = true
        label.attributedStringValue = Self.attributed(for: message)
        label.frame = CGRect(x: 44, y: (frame.height - 18) / 2, width: textRight - 44, height: 18)
        addSubview(label)

        // 缩略图 + 预览提示
        if let image {
            let thumb = NSImageView(frame: thumbRect)
            thumb.image = image
            thumb.imageScaling = .scaleProportionallyUpOrDown
            thumb.wantsLayer = true
            thumb.layer?.cornerRadius = 6
            thumb.layer?.masksToBounds = true
            thumb.layer?.borderWidth = 1
            thumb.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor
            addSubview(thumb)

            let hint = NSTextField(labelWithString: "点击预览")
            hint.font = .systemFont(ofSize: 9, weight: .medium)
            hint.textColor = .white
            hint.alignment = .center
            hint.wantsLayer = true
            hint.drawsBackground = true
            hint.backgroundColor = NSColor.black.withAlphaComponent(0.5)
            hint.layer?.cornerRadius = 3
            hint.layer?.masksToBounds = true
            let hw: CGFloat = 52
            hint.frame = CGRect(x: thumbRect.midX - hw / 2, y: thumbRect.minY + 4, width: hw, height: 14)
            addSubview(hint)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func attributed(for message: String) -> NSAttributedString {
        let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let ocrPrefix = "OCR 已复制："
        guard message.hasPrefix(ocrPrefix) else {
            return NSAttributedString(string: message, attributes: [.font: font, .foregroundColor: NSColor.labelColor])
        }
        let result = NSMutableAttributedString(string: ocrPrefix, attributes: [.font: font, .foregroundColor: NSColor.labelColor])
        result.append(NSAttributedString(string: String(message.dropFirst(ocrPrefix.count)),
                                         attributes: [.font: font, .foregroundColor: NSColor.systemBlue]))
        return result
    }
}

enum Toast {
    private static var current: ToastWindow?

    static func show(_ message: String, image: NSImage? = nil) {
        DispatchQueue.main.async {
            current?.close()
            let onPreview: (() -> Void)? = image.map { img in
                { ImagePreviewPanel.show(img) }
            }
            let window = ToastWindow(message: message, image: image, onPreview: onPreview)
            current = window
            window.orderFrontRegardless()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                if current === window {
                    window.close()
                    current = nil
                }
            }
        }
    }
}

final class ImagePreviewPanel: NSPanel {
    private static var shared: ImagePreviewPanel?

    static func show(_ image: NSImage) {
        shared?.close()
        let panel = ImagePreviewPanel(image: image)
        shared = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private init(image: NSImage) {
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
        let maxW = screen.width * 0.82
        let maxH = screen.height * 0.82
        let scale = min(maxW / image.size.width, maxH / image.size.height, 1.0)
        let size = CGSize(width: max(image.size.width * scale, 200), height: max(image.size.height * scale, 200))
        let origin = CGPoint(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2)
        super.init(
            contentRect: CGRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        isReleasedWhenClosed = false
        level = .floating
        hasShadow = true
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = ImagePreviewView(image: image, onClose: { [weak self] in self?.close() })
    }

    override var canBecomeKey: Bool { true }
}

private final class ImagePreviewView: NSView {
    private let image: NSImage
    private let onClose: () -> Void

    init(image: NSImage, onClose: @escaping () -> Void) {
        self.image = image
        self.onClose = onClose
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 12, yRadius: 12)
        NSColor.black.withAlphaComponent(0.05).setFill()
        path.fill()
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        image.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        NSColor.separatorColor.withAlphaComponent(0.3).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        onClose()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 || event.keyCode == 49 {
            onClose()
        } else {
            super.keyDown(with: event)
        }
    }
}
