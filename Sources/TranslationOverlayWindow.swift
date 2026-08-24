import AppKit

/// 覆盖式翻译结果窗口：盖在选区上，逐行用毛玻璃卡片覆盖原文并画出译文。
/// 交互（本轮）：Esc / 点击空白关闭；顶部「复制译文」按钮复制全部译文。
final class TranslationOverlayWindow: NSPanel {
    /// - Parameters:
    ///   - regionRect: 选区在全局 AppKit 坐标（左下原点）中的位置与大小。
    ///   - background: 选区截图，作为覆盖层底图，营造「盖在原文上」的观感。
    ///   - lines: 每行译文 + 其归一化 box（Vision 坐标，左下原点）。
    init(regionRect: CGRect, background: NSImage?, lines: [OCRLine]) {
        super.init(contentRect: regionRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        level = .screenSaver
        backgroundColor = .clear
        isOpaque = false
        isReleasedWhenClosed = false
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let view = TranslationOverlayView(
            frame: CGRect(origin: .zero, size: regionRect.size),
            background: background,
            lines: lines
        )
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

    private let background: NSImage?
    private let lines: [OCRLine]
    private let accent = AppSettings.shared.accentColor

    init(frame: CGRect, background: NSImage?, lines: [OCRLine]) {
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
        let copy = makeToolButton(title: "复制译文", symbol: "doc.on.doc")
        copy.target = self
        copy.action = #selector(copyTranslations)

        let close = makeToolButton(title: "关闭 (Esc)", symbol: "xmark")
        close.target = self
        close.action = #selector(closeTapped)

        let bar = NSStackView(views: [copy, close])
        bar.orientation = .horizontal
        bar.spacing = 8
        bar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bar)
        // 贴在选区右上角内侧。
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            bar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8)
        ])
    }

    private func makeToolButton(title: String, symbol: String) -> NSButton {
        let button = NSButton(title: "  \(title)", target: nil, action: nil)
        button.bezelStyle = .rounded
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        button.imagePosition = .imageLeading
        button.controlSize = .small
        button.font = .systemFont(ofSize: 11, weight: .medium)
        button.contentTintColor = .white
        button.wantsLayer = true
        button.isBordered = false
        button.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.62).cgColor
        button.layer?.cornerRadius = 8
        button.layer?.borderWidth = 1
        button.layer?.borderColor = accent.withAlphaComponent(0.6).cgColor
        return button
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
        // 点击空白区域关闭（工具栏按钮会自行拦截各自的点击）。
        onClose?()
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        // 底图：选区原始截图，让译文看起来是盖在原文上。
        background?.draw(in: bounds)

        let W = bounds.width
        let H = bounds.height
        for line in lines where !line.text.isEmpty {
            let rect = CGRect(x: line.box.minX * W,
                              y: line.box.minY * H,
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
        // 垂直居中。
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
