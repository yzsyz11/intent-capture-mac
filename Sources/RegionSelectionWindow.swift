import AppKit

final class RegionSelectionWindow: NSWindow {
    enum Mode {
        case region
        case point
    }

    var onRegion: ((CGRect) -> Void)?
    var onPoint: ((CGPoint) -> Void)?
    var onCancel: (() -> Void)?

    init(screen: NSScreen, mode: Mode) {
        let frame = screen.frame
        let view = RegionSelectionView(frame: CGRect(origin: .zero, size: frame.size), mode: mode)
        super.init(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        contentView = view
        level = .screenSaver
        backgroundColor = .clear
        isOpaque = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        view.onRegion = { [weak self] rect in
            self?.finishRegion(rect)
        }
        view.onPoint = { [weak self] point in
            self?.finishPoint(point)
        }
        view.onCancel = { [weak self] in
            self?.finishCancel()
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func show() {
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func finishRegion(_ rect: CGRect) {
        let callback = onRegion
        clearCallbacks()
        close()
        callback?(rect)
    }

    private func finishPoint(_ point: CGPoint) {
        let callback = onPoint
        clearCallbacks()
        close()
        callback?(point)
    }

    private func finishCancel() {
        let callback = onCancel
        clearCallbacks()
        close()
        callback?()
    }

    private func clearCallbacks() {
        onRegion = nil
        onPoint = nil
        onCancel = nil
    }
}

final class RegionSelectionView: NSView {
    let mode: RegionSelectionWindow.Mode
    var onRegion: ((CGRect) -> Void)?
    var onPoint: ((CGPoint) -> Void)?
    var onCancel: (() -> Void)?

    private var start: CGPoint?
    private var current: CGPoint?

    init(frame: CGRect, mode: RegionSelectionWindow.Mode) {
        self.mode = mode
        super.init(frame: frame)
        wantsLayer = true
        window?.acceptsMouseMovedEvents = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = event.locationInWindow
        if mode == .point {
            onPoint?(convertToScreen(point))
            return
        }
        start = point
        current = point
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        current = event.locationInWindow
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        current = event.locationInWindow
        guard let start, let current else { return }
        let localRect = CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(start.x - current.x),
            height: abs(start.y - current.y)
        )
        guard localRect.width > 4, localRect.height > 4 else {
            onCancel?()
            return
        }
        let a = convertToScreen(localRect.origin)
        let b = convertToScreen(CGPoint(x: localRect.maxX, y: localRect.maxY))
        let screenRect = CGRect(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(a.x - b.x),
            height: abs(a.y - b.y)
        )
        onRegion?(screenRect)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.36).setFill()
        bounds.fill()

        let instruction = mode == .point
            ? "点击一个像素复制颜色，Esc 取消"
            : "拖拽框选区域，松开后执行，Esc 取消"
        drawInstruction(instruction)

        guard let start, let current, mode == .region else { return }
        let rect = CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(start.x - current.x),
            height: abs(start.y - current.y)
        )
        NSColor.systemBlue.withAlphaComponent(0.22).setFill()
        rect.fill()
        NSColor.systemBlue.setStroke()
        NSBezierPath(rect: rect).stroke()
    }

    private func drawInstruction(_ value: String) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let text = NSString(string: value)
        let size = text.size(withAttributes: attrs)
        let rect = CGRect(x: (bounds.width - size.width) / 2, y: bounds.height - 72, width: size.width, height: size.height)
        text.draw(in: rect, withAttributes: attrs)
    }

    private func convertToScreen(_ point: CGPoint) -> CGPoint {
        guard let window else { return point }
        return window.convertPoint(toScreen: point)
    }
}
