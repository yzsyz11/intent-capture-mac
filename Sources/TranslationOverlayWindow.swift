import AppKit

/// 覆盖式翻译结果窗口：盖在选区上，逐行用毛玻璃卡片覆盖原文并画出译文。
/// 工具条永远放在选区外侧（优先下方，贴屏底则翻到上方），不遮挡译文。
/// 交互（本轮）：Esc / 点击空白关闭；「复制译文」复制全部译文。
final class TranslationOverlayWindow: NSPanel {
    private static let toolbarHeight: CGFloat = 40
    private static let gap: CGFloat = 10
    private static let minWidth: CGFloat = 240

    /// - Parameters:
    ///   - regionRect: 选区在全局 AppKit 坐标（左下原点）中的位置与大小。
    ///   - background: 选区截图，作为覆盖层底图。
    ///   - lines: 每行译文 + 其归一化 box（Vision 坐标，左下原点）。
    init(regionRect: CGRect, background: NSImage?, lines: [OCRLine]) {
        let screen = NSScreen.screens.first { $0.frame.intersects(regionRect) } ?? NSScreen.main
        let screenFrame = screen?.frame ?? regionRect

        let toolbar = Self.toolbarHeight
        let gap = Self.gap
        let width = max(regionRect.width, Self.minWidth)

        // 优先把工具条放选区下方；空间不够则放上方。
        let placeBelow = regionRect.minY - gap - toolbar >= screenFrame.minY
        let windowHeight = regionRect.height + gap + toolbar
        let windowOriginY = placeBelow ? regionRect.minY - gap - toolbar : regionRect.minY
        let windowFrame = CGRect(x: regionRect.minX, y: windowOriginY, width: width, height: windowHeight)

        // 选区内容（底图 + 译文卡片）在窗口内的位置。
        let contentRect = CGRect(x: 0,
                                 y: placeBelow ? gap + toolbar : 0,
                                 width: regionRect.width,
                                 height: regionRect.height)
        let toolbarRect = CGRect(x: 0,
                                 y: placeBelow ? 0 : regionRect.height + gap,
                                 width: width,
                                 height: toolbar)

        super.init(contentRect: windowFrame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        level = .screenSaver
        backgroundColor = .clear
        isOpaque = false
        isReleasedWhenClosed = false
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let view = TranslationOverlayView(frame: CGRect(origin: .zero, size: windowFrame.size),
                                          contentRect: contentRect,
                                          toolbarRect: toolbarRect,
                                          background: background,
                                          lines: lines)
        view.onClose = { [weak self] in self?.close() }
        contentView = view
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func show() {
        makeKeyAndOrderFront(nil)
        orderFrontRegardless()
    }
}

final class TranslationOverlayView: NSView {
    var onClose: (() -> Void)?

    private let contentRect: CGRect
    private let toolbarRect: CGRect
    private let background: NSImage?
    private let lines: [OCRLine]
    private let accent = AppSettings.shared.accentColor

    init(frame: CGRect, contentRect: CGRect, toolbarRect: CGRect, background: NSImage?, lines: [OCRLine]) {
        self.contentRect = contentRect
        self.toolbarRect = toolbarRect
        self.background = background
        self.lines = lines
        super.init(frame: frame)
        wantsLayer = true
        buildToolbar()

        alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            animator().alphaValue = 1
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    // MARK: - Toolbar

    private func buildToolbar() {
        let copy = OverlayPillButton(title: "复制译文", symbol: "doc.on.doc", accent: accent)
        copy.target = self
        copy.action = #selector(copyTranslations)

        let close = OverlayPillButton(title: "关闭", symbol: "xmark", accent: accent)
        close.target = self
        close.action = #selector(closeTapped)

        let bar = NSStackView(views: [copy, close])
        bar.orientation = .horizontal
        bar.spacing = 8
        bar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bar)
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: max(2, contentRect.minX)),
            bar.centerYAnchor.constraint(equalTo: bottomAnchor, constant: -(toolbarRect.minY + toolbarRect.height / 2))
        ])
    }

    // MARK: - Actions

    @objc private func copyTranslations() {
        let text = lines.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n")
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        onClose?()
        Toast.show("译文已复制")
    }

    @objc private func closeTapped() { onClose?() }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onClose?() } // Esc
        else { super.keyDown(with: event) }
    }

    override func mouseDown(with event: NSEvent) {
        // 点击空白关闭（工具栏按钮各自拦截自己的点击）。
        onClose?()
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        // 底图：选区原始截图，让译文看起来盖在原文上。
        background?.draw(in: contentRect)

        let W = contentRect.width
        let H = contentRect.height
        for line in lines where !line.text.isEmpty {
            let rect = CGRect(x: contentRect.minX + line.box.minX * W,
                              y: contentRect.minY + line.box.minY * H,
                              width: line.box.width * W,
                              height: line.box.height * H).insetBy(dx: -3, dy: -2)
            drawCard(in: rect, text: line.text)
        }
    }

    /// 单行：毛玻璃感深色圆角卡片盖住原文 + 自适应字号译文。
    private func drawCard(in rect: CGRect, text: String) {
        guard rect.width > 2, rect.height > 2 else { return }
        let radius = min(6, rect.height * 0.3)
        let card = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        NSColor.black.withAlphaComponent(0.72).setFill()
        card.fill()
        accent.withAlphaComponent(0.35).setStroke()
        card.lineWidth = 1
        card.stroke()

        let inset = rect.insetBy(dx: 4, dy: 1)
        let font = Self.fittedFont(for: text, in: inset.size)
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
            .paragraphStyle: style
        ]
        let str = NSString(string: text)
        let textSize = str.size(withAttributes: attrs)
        let drawRect = CGRect(x: inset.minX,
                              y: inset.minY + max(0, (inset.height - textSize.height) / 2),
                              width: inset.width,
                              height: min(textSize.height, inset.height))
        str.draw(in: drawRect, withAttributes: attrs)
    }

    /// 从「按 box 高度估的字号」起步，逐步缩小直到宽度放得下（有下限）。
    private static func fittedFont(for text: String, in size: CGSize) -> NSFont {
        var pt = max(9, min(size.height * 0.82, 34))
        let str = NSString(string: text)
        while pt > 9 {
            let font = NSFont.systemFont(ofSize: pt)
            let w = str.size(withAttributes: [.font: font]).width
            if w <= size.width { return font }
            pt -= 1
        }
        return NSFont.systemFont(ofSize: 9)
    }
}

/// 覆盖层工具条上的 App 风格毛玻璃胶囊按钮，带 hover 高亮。
final class OverlayPillButton: NSButton {
    private let accent: NSColor
    private let blur = NSVisualEffectView()

    init(title: String, symbol: String, accent: NSColor) {
        self.accent = accent
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        isBordered = false
        bezelStyle = .regularSquare
        imagePosition = .imageLeading
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        imageScaling = .scaleProportionallyDown
        contentTintColor = .white
        wantsLayer = true

        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 14
        blur.layer?.masksToBounds = true
        blur.layer?.borderWidth = 1
        blur.layer?.borderColor = accent.withAlphaComponent(0.55).cgColor
        blur.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blur, positioned: .below, relativeTo: nil)
        NSLayoutConstraint.activate([
            blur.leadingAnchor.constraint(equalTo: leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: trailingAnchor),
            blur.topAnchor.constraint(equalTo: topAnchor),
            blur.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: 28)
        ])

        attributedTitle = NSAttributedString(string: " " + title, attributes: [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 12, weight: .medium)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        size.width += 26   // 左右内边距，避免文字贴边
        size.height = 28
        return size
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    override func mouseEntered(with event: NSEvent) {
        blur.layer?.backgroundColor = accent.withAlphaComponent(0.30).cgColor
        blur.layer?.borderColor = accent.withAlphaComponent(0.9).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        blur.layer?.backgroundColor = NSColor.clear.cgColor
        blur.layer?.borderColor = accent.withAlphaComponent(0.55).cgColor
    }
}
