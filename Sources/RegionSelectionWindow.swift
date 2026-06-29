import AppKit

final class RegionSelectionWindow: NSPanel {
    enum Mode {
        case region
        case point
    }

    var onRegion: ((CGRect) -> Void)?
    var onPoint: ((CGPoint) -> Void)?
    var onCancel: (() -> Void)?

    init(screen: NSScreen, mode: Mode, backgroundCapture: CGImage? = nil) {
        let frame = screen.frame
        let view = RegionSelectionView(frame: CGRect(origin: .zero, size: frame.size), mode: mode, backgroundCapture: backgroundCapture)
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        contentView = view
        // screenSaver level ensures we cover the menu bar and capture all mouse events
        level = .screenSaver
        backgroundColor = .clear
        isOpaque = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        view.onRegion = { [weak self] rect in self?.finishRegion(rect) }
        view.onPoint  = { [weak self] pt   in self?.finishPoint(pt) }
        view.onCancel = { [weak self] in       self?.finishCancel() }
    }

    override var canBecomeKey: Bool  { true }
    override var canBecomeMain: Bool { true }

    func show() {
        makeKeyAndOrderFront(nil)
        orderFrontRegardless()
    }

    private func finishRegion(_ rect: CGRect) {
        let cb = onRegion; clearCallbacks(); close(); cb?(rect)
    }
    private func finishPoint(_ pt: CGPoint) {
        let cb = onPoint; clearCallbacks(); close(); cb?(pt)
    }
    private func finishCancel() {
        let cb = onCancel; clearCallbacks(); close(); cb?()
    }
    private func clearCallbacks() {
        onRegion = nil; onPoint = nil; onCancel = nil
    }
}

final class RegionSelectionView: NSView {
    let mode: RegionSelectionWindow.Mode
    var onRegion: ((CGRect) -> Void)?
    var onPoint:  ((CGPoint) -> Void)?
    var onCancel: (() -> Void)?

    private var start: CGPoint?
    private var current: CGPoint?
    private var mousePosition: CGPoint?
    private let backgroundCapture: CGImage?

    init(frame: CGRect, mode: RegionSelectionWindow.Mode, backgroundCapture: CGImage?) {
        self.mode = mode
        self.backgroundCapture = backgroundCapture
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways], owner: self))
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?() }
    }

    override func mouseMoved(with event: NSEvent) {
        mousePosition = event.locationInWindow
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let pt = event.locationInWindow
        if mode == .point { onPoint?(convertToScreen(pt)); return }
        start = pt; current = pt; needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        current = event.locationInWindow
        mousePosition = event.locationInWindow
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        current = event.locationInWindow
        guard let s = start, let c = current else { return }
        let local = CGRect(x: min(s.x, c.x), y: min(s.y, c.y),
                           width: abs(s.x - c.x), height: abs(s.y - c.y))
        guard local.width > 4, local.height > 4 else { onCancel?(); return }
        let a = convertToScreen(local.origin)
        let b = convertToScreen(CGPoint(x: local.maxX, y: local.maxY))
        onRegion?(CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
                         width: abs(a.x - b.x), height: abs(a.y - b.y)))
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.36).setFill()
        bounds.fill()

        if mode == .region {
            drawRegionMode()
        }

        if mode == .point, let pos = mousePosition, let bg = backgroundCapture {
            drawMagnifier(at: pos, image: bg)
        }

        let pos = mousePosition ?? current
        if let pos { drawCrosshair(at: pos) }

        if start == nil {
            let hint = mode == .point ? "点击一个像素复制颜色，Esc 取消"
                                      : "拖拽框选区域，松开后执行，Esc 取消"
            drawInstruction(hint)
        }
    }

    private func drawRegionMode() {
        guard let s = start, let c = current else { return }
        let rect = CGRect(x: min(s.x, c.x), y: min(s.y, c.y),
                          width: abs(s.x - c.x), height: abs(s.y - c.y))
        NSGraphicsContext.current?.cgContext.clear(rect)
        NSColor.systemBlue.withAlphaComponent(0.12).setFill()
        NSBezierPath(rect: rect).fill()
        let border = NSBezierPath(rect: rect)
        border.lineWidth = 1.5
        NSColor.systemBlue.setStroke()
        border.stroke()
        drawSizeLabel(rect: rect)
    }

    private func drawCrosshair(at pos: CGPoint) {
        NSColor.white.withAlphaComponent(0.55).setStroke()
        for path in [
            makeLine(from: CGPoint(x: 0, y: pos.y), to: CGPoint(x: bounds.width, y: pos.y)),
            makeLine(from: CGPoint(x: pos.x, y: 0), to: CGPoint(x: pos.x, y: bounds.height))
        ] {
            path.lineWidth = 1
            path.setLineDash([4, 4], count: 2, phase: 0)
            path.stroke()
        }
    }

    private func makeLine(from a: CGPoint, to b: CGPoint) -> NSBezierPath {
        let p = NSBezierPath(); p.move(to: a); p.line(to: b); return p
    }

    private func drawSizeLabel(rect: CGRect) {
        guard rect.width > 0, rect.height > 0 else { return }
        let scale = window?.backingScaleFactor ?? 1
        let label = "\(Int(rect.width * scale)) × \(Int(rect.height * scale))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let str = NSString(string: label)
        let size = str.size(withAttributes: attrs)
        let pad: CGFloat = 6
        let tagW = size.width + pad * 2
        let tagH = size.height + pad
        let tagX = rect.minX + (rect.width - tagW) / 2
        var tagY = rect.maxY + 6
        if tagY + tagH > bounds.height - 10 { tagY = rect.minY - tagH - 6 }
        let bg = CGRect(x: tagX, y: tagY, width: tagW, height: tagH)
        NSColor.black.withAlphaComponent(0.6).setFill()
        NSBezierPath(roundedRect: bg, xRadius: 4, yRadius: 4).fill()
        str.draw(at: CGPoint(x: tagX + pad, y: tagY + pad / 2), withAttributes: attrs)
    }

    private func drawInstruction(_ text: String) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let s = NSString(string: text)
        let size = s.size(withAttributes: attrs)
        s.draw(in: CGRect(x: (bounds.width - size.width) / 2, y: bounds.height - 72,
                          width: size.width, height: size.height), withAttributes: attrs)
    }

    // MARK: - Magnifier

    private func drawMagnifier(at pos: CGPoint, image: CGImage) {
        let scale = window?.backingScaleFactor ?? 2.0
        let imgCX = Int(pos.x * scale)
        let imgCY = Int((bounds.height - pos.y) * scale)

        let half = 6
        let gridN = half * 2 + 1  // 13 × 13
        let sX = max(0, imgCX - half)
        let sY = max(0, imgCY - half)
        let sW = min(gridN, image.width  - sX)
        let sH = min(gridN, image.height - sY)
        guard sW > 0, sH > 0 else { return }

        guard let crop = image.cropping(to: CGRect(x: sX, y: sY, width: sW, height: sH)) else { return }
        let rep = NSBitmapImageRep(cgImage: crop)

        let cell: CGFloat = 11
        let gW = CGFloat(sW) * cell
        let gH = CGFloat(sH) * cell
        let infoH: CGFloat = 30
        let pad: CGFloat = 8
        let totalW = gW + pad * 2
        let totalH = gH + infoH + pad * 2

        // Position: prefer lower-right of cursor, flip if near edge
        var ox = pos.x + 22
        var oy = pos.y + 12
        if ox + totalW > bounds.width  - 10 { ox = pos.x - totalW - 12 }
        if oy + totalH > bounds.height - 10 { oy = pos.y - totalH - 12 }
        ox = max(10, ox)
        oy = max(10, oy)

        // Container background
        let container = CGRect(x: ox, y: oy, width: totalW, height: totalH)
        let bgPath = NSBezierPath(roundedRect: container, xRadius: 10, yRadius: 10)
        NSColor.black.withAlphaComponent(0.88).setFill()
        bgPath.fill()
        NSColor.white.withAlphaComponent(0.12).setStroke()
        bgPath.lineWidth = 1
        bgPath.stroke()

        let gridLeft   = ox + pad
        let gridBottom = oy + infoH + pad

        // Pixel cells
        for row in 0..<sH {
            for col in 0..<sW {
                guard let c = rep.colorAt(x: col, y: row) else { continue }
                c.setFill()
                CGRect(x: gridLeft + CGFloat(col) * cell,
                       y: gridBottom + CGFloat(sH - 1 - row) * cell,
                       width: cell, height: cell).fill()
            }
        }

        // Grid lines
        NSColor.black.withAlphaComponent(0.22).setStroke()
        for i in 0...sW {
            let p = NSBezierPath()
            p.lineWidth = 0.5
            p.move(to: CGPoint(x: gridLeft + CGFloat(i) * cell, y: gridBottom))
            p.line(to: CGPoint(x: gridLeft + CGFloat(i) * cell, y: gridBottom + gH))
            p.stroke()
        }
        for i in 0...sH {
            let p = NSBezierPath()
            p.lineWidth = 0.5
            p.move(to: CGPoint(x: gridLeft,      y: gridBottom + CGFloat(i) * cell))
            p.line(to: CGPoint(x: gridLeft + gW, y: gridBottom + CGFloat(i) * cell))
            p.stroke()
        }

        // Center cell highlight
        let cCol = imgCX - sX
        let cRow = imgCY - sY
        if cCol >= 0, cCol < sW, cRow >= 0, cRow < sH {
            let cRect = CGRect(x: gridLeft + CGFloat(cCol) * cell,
                               y: gridBottom + CGFloat(sH - 1 - cRow) * cell,
                               width: cell, height: cell)
            let hp = NSBezierPath(rect: cRect.insetBy(dx: 0.5, dy: 0.5))
            hp.lineWidth = 1.5
            NSColor.white.setStroke()
            hp.stroke()

            // Color info row
            if let srgb = rep.colorAt(x: cCol, y: cRow)?.usingColorSpace(.sRGB) {
                let r = Int(round(srgb.redComponent   * 255))
                let g = Int(round(srgb.greenComponent * 255))
                let b = Int(round(srgb.blueComponent  * 255))
                let hex = String(format: "#%02X%02X%02X", r, g, b)

                let swW: CGFloat = 18
                let swY = oy + pad + (infoH - swW) / 2
                let swatchRect = CGRect(x: gridLeft, y: swY, width: swW, height: swW)
                srgb.setFill()
                NSBezierPath(roundedRect: swatchRect, xRadius: 3, yRadius: 3).fill()
                NSColor.white.withAlphaComponent(0.25).setStroke()
                NSBezierPath(roundedRect: swatchRect, xRadius: 3, yRadius: 3).stroke()

                let textAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
                    .foregroundColor: NSColor.white
                ]
                NSString(string: hex).draw(
                    at: CGPoint(x: gridLeft + swW + 6, y: oy + pad + (infoH - 15) / 2),
                    withAttributes: textAttrs
                )
            }
        }
    }

    private func convertToScreen(_ point: CGPoint) -> CGPoint {
        window?.convertPoint(toScreen: point) ?? point
    }
}
