import AppKit
import Carbon

final class ClipboardDockWindow: NSPanel {
    private let store: ClipboardHistoryStore
    private let dockView: ClipboardDockView
    private var outsideMouseMonitor: Any?
    private var localMouseMonitor: Any?

    init(store: ClipboardHistoryStore) {
        self.store = store
        self.dockView = ClipboardDockView(store: store)
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
        let width = min(screen.width - 48, 1160)
        let size = CGSize(width: width, height: 182)
        let rect = CGRect(x: screen.midX - width / 2, y: screen.minY + 18, width: size.width, height: size.height)
        super.init(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isReleasedWhenClosed = false
        contentView = dockView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func toggle() {
        isVisible ? hideDock() : showDock()
    }

    func showDock() {
        positionAboveDock()
        dockView.reload()
        makeKeyAndOrderFront(nil)
        startDismissMonitors()
    }

    func refresh() {
        dockView.reload()
    }

    func hideDock() {
        stopDismissMonitors()
        orderOut(nil)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            hideDock()
            return
        }
        super.keyDown(with: event)
    }

    private func positionAboveDock() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }

        let visible = screen.visibleFrame
        let width = min(visible.width - 48, 1160)
        let height: CGFloat = 182
        // Dock 上方：visibleFrame.minY 会避开底部 Dock 占用区域。
        let y = visible.minY + 18
        setFrame(CGRect(x: visible.midX - width / 2, y: y, width: width, height: height), display: true)
    }

    private func startDismissMonitors() {
        stopDismissMonitors()
        outsideMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            self?.hideIfMouseIsOutsideDock()
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            self?.hideIfMouseIsOutsideDock()
            return event
        }
    }

    private func stopDismissMonitors() {
        if let outsideMouseMonitor { NSEvent.removeMonitor(outsideMouseMonitor) }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        outsideMouseMonitor = nil
        localMouseMonitor = nil
    }

    private func hideIfMouseIsOutsideDock() {
        guard isVisible else { return }
        let point = NSEvent.mouseLocation
        if !frame.insetBy(dx: -2, dy: -2).contains(point) {
            hideDock()
        }
    }
}

final class ClipboardDockView: NSView {
    private let store: ClipboardHistoryStore
    private let effectView = NSVisualEffectView()
    private let scrollView = HorizontalWheelScrollView()
    private let stripView = ClipboardCardStripView()
    private let title = NSTextField(labelWithString: "剪贴板拓展坞")
    private let subtitle = NSTextField(labelWithString: "⌘D 呼出 / 鼠标横向滚动")
    private let emptyLabel = NSTextField(labelWithString: "复制文字、截图或色值后，会出现在这里")
    private let searchButton = DockSymbolButton(symbolName: "magnifyingglass", tooltip: "搜索")
    private let pinButton = DockSymbolButton(symbolName: "pin", tooltip: "固定")
    private let settingsButton = DockSymbolButton(symbolName: "gearshape", tooltip: "设置")
    private let closeButton = DockSymbolButton(symbolName: "xmark", tooltip: "关闭")
    private let clearButton = DockSymbolButton(symbolName: "trash", tooltip: "清空历史")
    private let indicatorView = ScrollIndicatorView(frame: .zero)

    init(store: ClipboardHistoryStore) {
        self.store = store
        super.init(frame: CGRect(x: 0, y: 0, width: 1160, height: 182))
        wantsLayer = true
        build()
        reload()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func reload() {
        stripView.configure(items: store.items, store: store)
        emptyLabel.isHidden = !store.items.isEmpty
        needsDisplay = true
        indicatorView.refresh()
    }

    override func layout() {
        super.layout()
        effectView.frame = bounds
        title.frame = CGRect(x: 24, y: bounds.height - 38, width: 150, height: 22)
        subtitle.frame = CGRect(x: 158, y: bounds.height - 35, width: 250, height: 17)
        closeButton.frame = CGRect(x: bounds.width - 44, y: bounds.height - 39, width: 24, height: 24)
        settingsButton.frame = CGRect(x: bounds.width - 76, y: bounds.height - 39, width: 24, height: 24)
        pinButton.frame = CGRect(x: bounds.width - 108, y: bounds.height - 39, width: 24, height: 24)
        searchButton.frame = CGRect(x: bounds.width - 140, y: bounds.height - 39, width: 24, height: 24)
        clearButton.frame = CGRect(x: bounds.width - 172, y: bounds.height - 39, width: 24, height: 24)
        scrollView.frame = CGRect(x: 20, y: 25, width: bounds.width - 40, height: 108)
        emptyLabel.frame = CGRect(x: 24, y: 70, width: bounds.width - 48, height: 24)
        indicatorView.frame = CGRect(x: bounds.midX - 90, y: 16, width: 180, height: 4)
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 20, yRadius: 20)
        NSColor.white.withAlphaComponent(0.045).setFill()
        path.fill()
        NSColor.white.withAlphaComponent(0.38).setStroke()
        path.lineWidth = 1
        path.stroke()
        drawContentBand()
    }

    private func build() {
        effectView.material = .underWindowBackground
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.alphaValue = 0.58
        effectView.layer?.cornerRadius = 20
        effectView.layer?.masksToBounds = true
        addSubview(effectView)
        indicatorView.metricsProvider = { [weak self] in
            self?.scrollMetrics() ?? (progress: 0, visibleRatio: 1, canScroll: false)
        }
        addSubview(indicatorView)
        scrollView.onScroll = { [weak self] in
            // Only the small indicator layer needs to move every frame — invalidating
            // the whole 1160x182 panel here was the actual cause of scroll jank.
            self?.indicatorView.refresh()
        }

        title.font = .systemFont(ofSize: 17, weight: .semibold)
        title.textColor = .labelColor
        addSubview(title)

        subtitle.font = .systemFont(ofSize: 12, weight: .regular)
        subtitle.textColor = .secondaryLabelColor
        addSubview(subtitle)

        closeButton.target = self
        closeButton.action = #selector(closePanel)
        closeButton.autoresizingMask = [.minXMargin, .minYMargin]
        addSubview(closeButton)

        settingsButton.autoresizingMask = [.minXMargin, .minYMargin]
        addSubview(settingsButton)

        pinButton.autoresizingMask = [.minXMargin, .minYMargin]
        addSubview(pinButton)

        searchButton.autoresizingMask = [.minXMargin, .minYMargin]
        addSubview(searchButton)

        clearButton.target = self
        clearButton.action = #selector(clearHistory)
        clearButton.autoresizingMask = [.minXMargin, .minYMargin]
        addSubview(clearButton)

        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.horizontalScrollElasticity = .allowed
        scrollView.verticalScrollElasticity = .none
        scrollView.documentView = stripView
        addSubview(scrollView)

        emptyLabel.alignment = .center
        emptyLabel.font = .systemFont(ofSize: 13, weight: .medium)
        emptyLabel.textColor = .secondaryLabelColor
        addSubview(emptyLabel)
    }

    @objc private func closePanel() {
        (window as? ClipboardDockWindow)?.hideDock()
    }

    @objc private func clearHistory() {
        store.clear()
    }

    private func drawContentBand() {
        let band = CGRect(x: 16, y: 10, width: bounds.width - 32, height: 128)
        let path = NSBezierPath(roundedRect: band, xRadius: 14, yRadius: 14)
        NSColor.white.withAlphaComponent(0.075).setFill()
        path.fill()
        NSColor.white.withAlphaComponent(0.16).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private func scrollMetrics() -> (progress: CGFloat, visibleRatio: CGFloat, canScroll: Bool) {
        guard let documentView = scrollView.documentView else {
            return (0, 1, false)
        }
        let contentWidth = documentView.bounds.width
        let visibleWidth = scrollView.contentView.bounds.width
        guard contentWidth > visibleWidth, visibleWidth > 0 else {
            return (0, 1, false)
        }
        let maxOffset = contentWidth - visibleWidth
        let offset = min(max(scrollView.contentView.bounds.minX, 0), maxOffset)
        return (offset / maxOffset, visibleWidth / contentWidth, true)
    }
}

// Backed by CALayers instead of Core Graphics draw(_:) so a scroll-driven position
// update is a cheap GPU-composited layer move, not a full redraw of this view.
final class ScrollIndicatorView: NSView {
    private let trackLayer = CALayer()
    private let thumbLayer = CALayer()
    var metricsProvider: (() -> (progress: CGFloat, visibleRatio: CGFloat, canScroll: Bool))?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        trackLayer.backgroundColor = NSColor.black.withAlphaComponent(0.24).cgColor
        layer?.addSublayer(trackLayer)
        thumbLayer.backgroundColor = NSColor.white.withAlphaComponent(0.92).cgColor
        layer?.addSublayer(thumbLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        trackLayer.frame = bounds
        trackLayer.cornerRadius = bounds.height / 2
        thumbLayer.cornerRadius = bounds.height / 2
        refresh()
    }

    func refresh() {
        let metrics = metricsProvider?() ?? (progress: 0, visibleRatio: 1, canScroll: false)
        let thumbWidth = max(36, bounds.width * metrics.visibleRatio)
        let thumbX = (bounds.width - thumbWidth) * metrics.progress
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        thumbLayer.frame = CGRect(x: thumbX, y: 0, width: thumbWidth, height: bounds.height)
        thumbLayer.backgroundColor = NSColor.white.withAlphaComponent(metrics.canScroll ? 0.92 : 0.32).cgColor
        CATransaction.commit()
    }
}

final class HorizontalWheelScrollView: NSScrollView {
    var onScroll: (() -> Void)?
    private var momentumTimer: Timer?
    private var velocity: CGFloat = 0

    override func scrollWheel(with event: NSEvent) {
        let horizontalIntent = abs(event.scrollingDeltaX) >= abs(event.scrollingDeltaY)
        let rawDelta = horizontalIntent ? event.scrollingDeltaX : event.scrollingDeltaY
        // scrollingDeltaY is positive when the user scrolls up/left with natural
        // scrolling on; our content offset needs the opposite sign to track the gesture.
        let signedDelta = -rawDelta

        if event.hasPreciseScrollingDeltas {
            // Trackpad already streams smooth per-frame deltas, including its own
            // momentum phase after the finger lifts — just follow it directly.
            stopMomentum()
            scrollHorizontally(by: signedDelta * 1.8)
        } else {
            // A mechanical mouse wheel reports large discrete notches; snapping the
            // content by the full notch each time feels stuttery. Feed the notch into
            // a velocity that a decay timer glides smoothly instead.
            velocity += signedDelta * 15
            startMomentumIfNeeded()
        }
    }

    private func startMomentumIfNeeded() {
        guard momentumTimer == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            guard abs(self.velocity) > 0.5 else {
                timer.invalidate()
                self.momentumTimer = nil
                self.velocity = 0
                return
            }
            self.scrollHorizontally(by: self.velocity)
            self.velocity *= 0.85
        }
        momentumTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopMomentum() {
        momentumTimer?.invalidate()
        momentumTimer = nil
        velocity = 0
    }

    func scrollHorizontally(by delta: CGFloat) {
        guard let documentView else { return }
        let clip = contentView
        let maxX = max(documentView.bounds.width - clip.bounds.width, 0)
        let nextX = min(max(clip.bounds.origin.x + delta, 0), maxX)
        clip.scroll(to: CGPoint(x: nextX, y: 0))
        reflectScrolledClipView(clip)
        onScroll?()
    }
}

final class ClipboardCardStripView: NSView {
    private var cardViews: [ClipboardCardView] = []

    func configure(items: [ClipboardHistoryItem], store: ClipboardHistoryStore) {
        cardViews.forEach { $0.removeFromSuperview() }
        cardViews = items.map { item in
            ClipboardCardView(item: item, store: store)
        }
        cardViews.forEach(addSubview)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let cardWidth: CGFloat = 180
        let gap: CGFloat = 12
        var x: CGFloat = 4
        for card in cardViews {
            card.frame = CGRect(x: x, y: 2, width: cardWidth, height: 98)
            x += cardWidth + gap
        }
        frame.size = CGSize(width: max(x + 8, superview?.bounds.width ?? x), height: 104)
    }

    override var isFlipped: Bool { true }
}

final class ClipboardCardView: NSView, NSTextFieldDelegate {
    private let item: ClipboardHistoryItem
    private let store: ClipboardHistoryStore
    private let previewButton = ClipboardPreviewButton()
    private var isHovering = false
    private var editField: NSTextField?
    private var pendingSingleClick: DispatchWorkItem?

    init(item: ClipboardHistoryItem, store: ClipboardHistoryStore) {
        self.item = item
        self.store = store
        super.init(frame: .zero)
        wantsLayer = true
        toolTip = "单击复制并收起，双击编辑，右键删除"
        previewButton.target = self
        previewButton.action = #selector(previewItem)
        addSubview(previewButton)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }

    override func layout() {
        super.layout()
        previewButton.frame = CGRect(x: bounds.width - 56, y: 8, width: 44, height: 22)
        editField?.frame = bounds.insetBy(dx: 10, dy: 10)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        needsDisplay = true
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseDown(with event: NSEvent) {
        guard editField == nil else { return }
        if event.clickCount >= 2 {
            pendingSingleClick?.cancel()
            pendingSingleClick = nil
            beginEditingIfPossible()
            return
        }
        // A double-click arrives as a second mouseDown with clickCount == 2, so delay
        // the single-click action long enough for that second click to cancel it —
        // otherwise the dock would already be closed before the double-click lands.
        let workItem = DispatchWorkItem { [weak self] in self?.performCopyAndClose() }
        pendingSingleClick = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval, execute: workItem)
    }

    private func performCopyAndClose() {
        store.restore(item)
        Toast.show("复制成功，已放回系统剪贴板：\(item.detail)")
        (window as? ClipboardDockWindow)?.hideDock()
    }

    private func beginEditingIfPossible() {
        guard item.kind != .image else {
            ClipboardPreviewWindow.show(item: item, image: store.image(for: item))
            return
        }
        let field = NSTextField(frame: bounds.insetBy(dx: 10, dy: 10))
        field.stringValue = item.preview
        field.font = .systemFont(ofSize: 12, weight: .medium)
        field.isBordered = true
        field.bezelStyle = .roundedBezel
        field.delegate = self
        field.target = self
        field.action = #selector(commitEdit(_:))
        addSubview(field)
        editField = field
        window?.makeFirstResponder(field)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        commitEdit(editField)
    }

    @objc private func commitEdit(_ sender: NSTextField?) {
        guard let field = sender ?? editField else { return }
        let text = field.stringValue
        field.removeFromSuperview()
        editField = nil
        if text != item.preview {
            store.update(item, newText: text)
            Toast.show("已自动保存")
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let deleteItem = NSMenuItem(title: "删除这条历史", action: #selector(deleteItem), keyEquivalent: "")
        deleteItem.target = self
        menu.addItem(deleteItem)
        return menu
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
        (isHovering ? NSColor.white.withAlphaComponent(0.40) : NSColor.white.withAlphaComponent(0.28)).setFill()
        path.fill()
        NSColor.white.withAlphaComponent(isHovering ? 0.64 : 0.38).setStroke()
        path.lineWidth = 1
        path.stroke()

        drawKindPill()
        switch item.kind {
        case .image:
            drawImageCard()
        case .color:
            drawColorCard()
        case .link:
            drawTextCard(accent: NSColor.systemBlue)
        case .text:
            drawTextCard(accent: NSColor.labelColor)
        }
    }

    private func drawKindPill() {
        let label = "\(item.kind.categoryTitle) · \(item.relativeTimeText)"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        NSString(string: label).draw(in: CGRect(x: 12, y: 11, width: bounds.width - 76, height: 14), withAttributes: attrs)
    }

    private func drawTextCard(accent: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        paragraph.maximumLineHeight = 18
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: accent,
            .paragraphStyle: paragraph
        ]
        NSString(string: item.preview).draw(in: CGRect(x: 12, y: 33, width: bounds.width - 24, height: 52), withAttributes: attrs)
    }

    private func drawImageCard() {
        let imageRect = CGRect(x: 12, y: 31, width: bounds.width - 24, height: 56)
        guard let image = store.image(for: item) else {
            drawTextCard(accent: .secondaryLabelColor)
            return
        }
        let clip = NSBezierPath(roundedRect: imageRect, xRadius: 7, yRadius: 7)
        NSGraphicsContext.saveGraphicsState()
        clip.addClip()
        // Fill (crop-to-cover) instead of fit: fitting left visible letterbox padding
        // around the thumbnail, which read as broken/undersized inside the card.
        let fillRect = image.aspectFillRect(in: imageRect, pixelSize: item.pixelSizeValue)
        image.draw(in: fillRect, from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        NSColor.black.withAlphaComponent(0.16).setStroke()
        clip.stroke()
    }

    private func drawColorCard() {
        let swatch = CGRect(x: 12, y: 34, width: bounds.width - 24, height: 38)
        let color = NSColor.fromClipboardString(item.preview) ?? NSColor(calibratedRed: 0.18, green: 0.65, blue: 0.78, alpha: 1)
        let path = NSBezierPath(roundedRect: swatch, xRadius: 8, yRadius: 8)
        color.setFill()
        path.fill()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        NSString(string: item.preview).draw(in: CGRect(x: 12, y: 78, width: bounds.width - 24, height: 18), withAttributes: attrs)
    }

    @objc private func previewItem() {
        ClipboardPreviewWindow.show(item: item, image: store.image(for: item))
    }

    @objc private func deleteItem() {
        store.delete(item)
        Toast.show("已删除这条剪贴板历史")
    }
}

final class ClipboardPreviewWindow: NSPanel {
    private static var current: ClipboardPreviewWindow?

    static func show(item: ClipboardHistoryItem, image: NSImage?) {
        current?.close()
        let panel = ClipboardPreviewWindow(item: item, image: image)
        current = panel
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    init(item: ClipboardHistoryItem, image: NSImage?) {
        super.init(
            contentRect: CGRect(x: 0, y: 0, width: 620, height: 420),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        title = "剪贴板预览"
        isReleasedWhenClosed = false
        contentView = ClipboardPreviewView(item: item, image: image)
    }
}

final class ClipboardPreviewView: NSView {
    private let item: ClipboardHistoryItem
    private let image: NSImage?

    init(item: ClipboardHistoryItem, image: NSImage?) {
        self.item = item
        self.image = image
        super.init(frame: CGRect(x: 0, y: 0, width: 620, height: 420))
        build()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func build() {
        if let image {
            let imageView = NSImageView(frame: bounds.insetBy(dx: 24, dy: 24))
            imageView.autoresizingMask = [.width, .height]
            imageView.image = image
            imageView.imageScaling = .scaleProportionallyUpOrDown
            addSubview(imageView)
            return
        }

        let scroll = NSScrollView(frame: bounds.insetBy(dx: 18, dy: 18))
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        let text = NSTextView(frame: scroll.bounds)
        text.isEditable = false
        text.isSelectable = true
        text.string = item.preview
        text.font = .systemFont(ofSize: 15)
        text.textColor = .labelColor
        text.backgroundColor = .clear
        scroll.documentView = text
        addSubview(scroll)
    }
}

final class DockIconButton: NSButton {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 12
    }

    convenience init(title: String, target: AnyObject?, action: Selector?) {
        self.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        font = .systemFont(ofSize: 17, weight: .medium)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class DockTextButton: NSButton {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        font = .systemFont(ofSize: 12, weight: .medium)
    }

    convenience init(title: String, target: AnyObject?, action: Selector?) {
        self.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class DockSymbolButton: NSButton {
    init(symbolName: String, tooltip: String) {
        super.init(frame: .zero)
        title = ""
        image = NSImage(systemSymbolName: symbolName, accessibilityDescription: tooltip)
        imagePosition = .imageOnly
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 12
        contentTintColor = .secondaryLabelColor
        toolTip = tooltip
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 12, yRadius: 12)
        NSColor.white.withAlphaComponent(isHighlighted ? 0.24 : 0.12).setFill()
        path.fill()
        NSColor.white.withAlphaComponent(0.22).setStroke()
        path.lineWidth = 1
        path.stroke()
        super.draw(dirtyRect)
    }
}

final class ClipboardPreviewButton: NSButton {
    init() {
        super.init(frame: .zero)
        title = "预览"
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 8
        controlSize = .small
        font = .systemFont(ofSize: 11, weight: .semibold)
        toolTip = "查看完整内容"
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        NSColor.white.withAlphaComponent(isHighlighted ? 0.28 : 0.16).setFill()
        path.fill()
        NSColor.white.withAlphaComponent(0.28).setStroke()
        path.lineWidth = 1
        path.stroke()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        let text = NSString(string: title)
        let size = text.size(withAttributes: attrs)
        text.draw(at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attrs)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private extension NSColor {
    static func fromClipboardString(_ value: String) -> NSColor? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("#") {
            let hex = String(trimmed.dropFirst())
            guard hex.count == 6, let int = Int(hex, radix: 16) else { return nil }
            return NSColor(
                calibratedRed: CGFloat((int >> 16) & 0xff) / 255,
                green: CGFloat((int >> 8) & 0xff) / 255,
                blue: CGFloat(int & 0xff) / 255,
                alpha: 1
            )
        }
        return nil
    }
}

private extension ClipboardHistoryKind {
    var categoryTitle: String {
        switch self {
        case .text: return "文字"
        case .image: return "图片"
        case .color: return "颜色"
        case .link: return "链接"
        }
    }
}

private extension ClipboardHistoryItem {
    var pixelSizeValue: CGSize? {
        guard let width = imageWidth, let height = imageHeight, width > 0, height > 0 else { return nil }
        return CGSize(width: width, height: height)
    }

    var relativeTimeText: String {
        let seconds = max(0, Int(Date().timeIntervalSince(createdAt)))
        if seconds < 60 { return seconds < 8 ? "刚刚" : "\(seconds)秒前" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)分钟前" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)小时前" }
        let days = hours / 24
        return "\(days)天前"
    }
}

private extension NSImage {
    // `size` can disagree with the source's actual pixel aspect ratio once an
    // NSImage round-trips through disk (DPI metadata, HiDPI reps, etc.), which is
    // what was squashing thumbnails. The stored pixel dimensions are ground truth.
    // Fill (not fit): scale to cover the target and crop the overflow so the
    // thumbnail has no letterbox padding around it.
    func aspectFillRect(in target: CGRect, pixelSize: CGSize? = nil) -> CGRect {
        let sourceSize = pixelSize ?? size
        guard sourceSize.width > 0, sourceSize.height > 0, target.width > 0, target.height > 0 else {
            return target
        }
        let scale = max(target.width / sourceSize.width, target.height / sourceSize.height)
        let width = sourceSize.width * scale
        let height = sourceSize.height * scale
        return CGRect(x: target.midX - width / 2, y: target.midY - height / 2, width: width, height: height)
    }
}
