import AppKit
import CoreGraphics
import Foundation
import Vision

final class CaptureService {
    private let settings = AppSettings.shared
    private var activeSelectionWindow: RegionSelectionWindow?

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
            Toast.show("截图已复制，未保存文件")
        case .screenshotSave:
            save(image, copyAfterSave: false)
        case .screenshotSaveAndCopy:
            save(image, copyAfterSave: true)
        case .ocrCopy:
            recognize(image)
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
        let selector = RegionSelectionWindow(screen: Self.currentMouseScreen(), mode: .point)
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
                Toast.show("已保存并复制：\(url.path)")
            } else {
                Toast.show("已保存：\(url.path)")
            }
        } catch {
            Toast.show("保存失败：\(error.localizedDescription)")
        }
    }

    private func recognize(_ image: NSImage) {
        guard let cgImage = image.ocrPreparedCGImage else {
            Toast.show("OCR 失败")
            return
        }

        let request = VNRecognizeTextRequest { request, error in
            if let error = error {
                DispatchQueue.main.async { Toast.show("OCR 失败：\(error.localizedDescription)") }
                return
            }
            let text = (request.results as? [VNRecognizedTextObservation])?
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n") ?? ""
            DispatchQueue.main.async {
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    Toast.show("未识别到文字")
                    return
                }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                Toast.show("OCR 已复制")
            }
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
    init(message: String) {
        let size = CGSize(width: 380, height: 56)
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
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = ToastView(message: message)
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
            case .success: return NSColor(calibratedRed: 0.18, green: 0.65, blue: 0.78, alpha: 1)
            case .warning: return NSColor(calibratedRed: 0.94, green: 0.61, blue: 0.20, alpha: 1)
            case .failure: return NSColor(calibratedRed: 0.88, green: 0.25, blue: 0.28, alpha: 1)
            case .info: return NSColor(calibratedRed: 0.34, green: 0.72, blue: 0.92, alpha: 1)
            }
        }
    }

    private let message: String
    private let tone: Tone

    init(message: String) {
        self.message = message
        self.tone = Self.tone(for: message)
        super.init(frame: CGRect(x: 0, y: 0, width: 380, height: 56))
        wantsLayer = true
        alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            self.animator().alphaValue = 1
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        let card = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: card, xRadius: 14, yRadius: 14)

        // Darker background for better contrast
        NSColor.windowBackgroundColor.withAlphaComponent(0.85).setFill()
        path.fill()

        // Brighter border
        NSColor.separatorColor.withAlphaComponent(0.55).setStroke()
        path.lineWidth = 1
        path.stroke()

        // Left accent strip - bigger
        let strip = NSBezierPath(roundedRect: CGRect(x: 9, y: 12, width: 4, height: bounds.height - 24), xRadius: 2, yRadius: 2)
        tone.color.setFill()
        strip.fill()

        // Solid color dot instead of faint circle
        tone.color.setFill()
        NSBezierPath(ovalIn: CGRect(x: 22, y: 20, width: 14, height: 14)).fill()

        // White icon in the dot
        tone.color.withAlphaComponent(0.9).setFill()
        let iconPath = NSBezierPath()
        switch tone {
        case .success:
            // Checkmark
            iconPath.move(to: CGPoint(x: 26, y: 27))
            iconPath.line(to: CGPoint(x: 29, y: 30))
            iconPath.line(to: CGPoint(x: 33, y: 23))
            NSColor.white.withAlphaComponent(0.9).setStroke()
            iconPath.lineWidth = 2
            iconPath.stroke()
        case .warning:
            // Exclamation
            iconPath.move(to: CGPoint(x: 29, y: 22))
            iconPath.line(to: CGPoint(x: 29, y: 28))
            iconPath.move(to: CGPoint(x: 29, y: 31))
            iconPath.line(to: CGPoint(x: 29, y: 32))
            NSColor.white.withAlphaComponent(0.9).setStroke()
            iconPath.lineWidth = 2.2
            iconPath.stroke()
        case .failure:
            // X
            iconPath.move(to: CGPoint(x: 26, y: 23))
            iconPath.line(to: CGPoint(x: 32, y: 31))
            iconPath.move(to: CGPoint(x: 32, y: 23))
            iconPath.line(to: CGPoint(x: 26, y: 31))
            NSColor.white.withAlphaComponent(0.9).setStroke()
            iconPath.lineWidth = 2.2
            iconPath.stroke()
        case .info:
            // i
            iconPath.move(to: CGPoint(x: 29, y: 24))
            iconPath.line(to: CGPoint(x: 29, y: 25))
            iconPath.move(to: CGPoint(x: 29, y: 27))
            iconPath.line(to: CGPoint(x: 29, y: 32))
            NSColor.white.withAlphaComponent(0.9).setStroke()
            iconPath.lineWidth = 2
            iconPath.stroke()
        }

        // Text - bigger, semibold
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        let textRect = CGRect(x: 46, y: 16, width: bounds.width - 56, height: 24)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        var merged = attrs
        merged[.paragraphStyle] = paragraph
        NSString(string: message).draw(in: textRect, withAttributes: merged)
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

enum Toast {
    private static var current: ToastWindow?

    static func show(_ message: String) {
        DispatchQueue.main.async {
            current?.close()
            let window = ToastWindow(message: message)
            current = window
            window.orderFrontRegardless()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                if current === window {
                    window.close()
                    current = nil
                }
            }
        }
    }
}
