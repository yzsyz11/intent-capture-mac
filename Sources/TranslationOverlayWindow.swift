import AppKit

/// 从 app bundle Resources 加载翻译相关图标（打包时由 package-macos.sh 从 Assets/icon 拷入）。
enum TranslationAsset {
    static func image(_ name: String) -> NSImage? {
        if let url = Bundle.main.url(forResource: name, withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return NSImage(named: name)
    }
}

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
    private var showingOriginal = false
    private weak var compareButton: OverlayPillButton?

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
        let compare = OverlayPillButton(icon: TranslationAsset.image("duibi"), accent: accent)
        compare.target = self
        compare.action = #selector(toggleOriginal)
        compare.toolTip = "对照原文（再按切回译文）"
        compareButton = compare

        let copy = OverlayPillButton(icon: TranslationAsset.image("fuzhi"), accent: accent)
        copy.target = self
        copy.action = #selector(copyTranslations)
        copy.toolTip = "复制译文"

        let close = OverlayPillButton(icon: TranslationAsset.image("guanbi"), accent: accent)
        close.target = self
        close.action = #selector(closeTapped)
        close.toolTip = "关闭"

        let bar = NSStackView(views: [compare, copy, close])
        bar.orientation = .horizontal
        bar.spacing = 8
        bar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bar)
        // 放到选区右下角。
        NSLayoutConstraint.activate([
            bar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            bar.centerYAnchor.constraint(equalTo: bottomAnchor, constant: -(toolbarRect.minY + toolbarRect.height / 2))
        ])
    }

    // MARK: - Actions

    /// 对照：隐藏译文卡片露出原文截图，再按切回。
    @objc private func toggleOriginal() {
        showingOriginal.toggle()
        compareButton?.setActive(showingOriginal)
        needsDisplay = true
    }

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

        // 对照模式下只显示原文（不画译文卡片）。
        guard !showingOriginal else { return }

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

/// 覆盖层工具条上的纯图标毛玻璃胶囊按钮：浅色磨砂底（深色图标才清晰），带 hover 与激活态。
/// 图标用独立 `NSImageView` 叠在磨砂**之上**（NSButton 自绘图标会被子视图磨砂盖住，故不走 image）。
final class OverlayPillButton: NSButton {
    private let accent: NSColor
    private let blur = NSVisualEffectView()
    private let iconView = NSImageView()
    private var active = false

    init(icon: NSImage?, accent: NSColor) {
        self.accent = accent
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        isBordered = false
        title = ""
        imagePosition = .noImage
        wantsLayer = true

        // 浅色磨砂底：强制 aqua 外观，保证在任意截图上深色图标都清晰。
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.appearance = NSAppearance(named: .aqua)
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 9
        blur.layer?.masksToBounds = true
        blur.layer?.borderWidth = 1
        blur.layer?.borderColor = accent.withAlphaComponent(0.5).cgColor
        blur.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blur)

        if let icon { icon.isTemplate = false }  // 保留原图颜色
        iconView.image = icon
        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)   // 叠在磨砂之上

        NSLayoutConstraint.activate([
            blur.leadingAnchor.constraint(equalTo: leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: trailingAnchor),
            blur.topAnchor.constraint(equalTo: topAnchor),
            blur.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthAnchor.constraint(equalToConstant: 34),
            heightAnchor.constraint(equalToConstant: 28),
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    /// 子视图（磨砂/图标）不得吞掉点击，统一交给按钮自身。
    override func hitTest(_ point: NSPoint) -> NSView? {
        return super.hitTest(point) != nil ? self : nil
    }

    /// 激活态（用于「对照」按钮按下时高亮）。
    func setActive(_ on: Bool) {
        active = on
        blur.layer?.backgroundColor = on ? accent.withAlphaComponent(0.5).cgColor : NSColor.clear.cgColor
        blur.layer?.borderColor = (on ? accent : accent.withAlphaComponent(0.5)).cgColor
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    override func mouseEntered(with event: NSEvent) {
        guard !active else { return }
        blur.layer?.backgroundColor = accent.withAlphaComponent(0.30).cgColor
        blur.layer?.borderColor = accent.withAlphaComponent(0.9).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        guard !active else { return }
        blur.layer?.backgroundColor = NSColor.clear.cgColor
        blur.layer?.borderColor = accent.withAlphaComponent(0.5).cgColor
    }
}
