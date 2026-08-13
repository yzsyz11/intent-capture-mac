import AppKit

/// 中键长按呼出的环形动作选择器。
/// 生命周期：按下越过延时 → 展示长按进度环（present-progress）→ 达到阈值绽放成轮盘（bloom）。
/// 轮盘为磨砂玻璃圆盘，扇区无缝拼接、默认透明，仅选中扇区染青色并用弹簧动画向外鼓出（果冻质感）。
final class RadialMenuWindow: NSPanel {
    private let menuView: RadialMenuView

    /// anchor 为全局 AppKit 坐标（左下原点），即中键按下的位置。
    init(anchor: CGPoint, actions: [CaptureAction]) {
        let screen = NSScreen.screens.first { $0.frame.contains(anchor) }
            ?? NSScreen.main
            ?? NSScreen.screens.first!
        let frame = screen.frame
        let centerInView = CGPoint(x: anchor.x - frame.minX, y: anchor.y - frame.minY)
        menuView = RadialMenuView(frame: CGRect(origin: .zero, size: frame.size),
                                  center: centerInView,
                                  actions: actions,
                                  backingScale: screen.backingScaleFactor)

        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .popUpMenu
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        contentView = menuView
    }

    /// 展示长按进度环，duration 为进度环转满一圈的时长。
    func presentProgress(duration: TimeInterval) {
        alphaValue = 0
        orderFrontRegardless()
        menuView.startProgress(duration: duration)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.10
            animator().alphaValue = 1
        }
    }

    /// 进度环绽放成轮盘。
    func bloomIntoWheel() {
        menuView.bloom()
    }

    /// global 为全局 AppKit 坐标，实时更新选中扇区。
    func updateCursor(_ global: CGPoint) {
        let point = CGPoint(x: global.x - frame.minX, y: global.y - frame.minY)
        menuView.update(cursor: point)
    }

    /// 返回当前选中的动作；停在中心死区时返回 nil。
    func selectedAction() -> CaptureAction? {
        menuView.selectedAction()
    }

    func dismiss(completion: @escaping () -> Void) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.close()
            completion()
        })
    }
}

private final class RadialMenuView: NSView {
    private struct Sector {
        let action: CaptureAction
        let centerDeg: CGFloat
        let shape: CAShapeLayer
        let label: CALayer
        let icon: CALayer
        let title: CATextLayer
        let labelBase: CGPoint
        let normalIcon: CGImage?
        let selectedIcon: CGImage?
    }

    private var accent: NSColor { AppSettings.shared.accentColor }
    private let r0: CGFloat = 58
    private let r1: CGFloat = 120
    private let bulge: CGFloat = 16
    private let radius: CGFloat = 172          // contentLayer 半宽
    private let center: CGPoint                // 圆盘中心（view 坐标）
    private let backingScale: CGFloat

    private let contentLayer = CALayer()
    private let wheelLayer = CALayer()         // 轮盘整体（进度阶段隐藏）
    private let progressTrack = CAShapeLayer()
    private let progressRing = CAShapeLayer()
    private var sectors: [Sector] = []
    private var hubTitle = CATextLayer()
    private var hubSub = CATextLayer()
    private var selectedIndex = -1
    private var bloomed = false

    private var localCenter: CGPoint { CGPoint(x: radius, y: radius) }

    init(frame: CGRect, center: CGPoint, actions: [CaptureAction], backingScale: CGFloat) {
        self.center = center
        self.backingScale = backingScale
        super.init(frame: frame)
        wantsLayer = true
        build(actions: actions)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: Build

    private func build(actions: [CaptureAction]) {
        contentLayer.frame = CGRect(x: center.x - radius, y: center.y - radius,
                                    width: radius * 2, height: radius * 2)
        contentLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        contentLayer.position = center
        layer?.addSublayer(contentLayer)

        // 轮盘整体分组，便于统一做绽放缩放
        wheelLayer.frame = contentLayer.bounds
        wheelLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        wheelLayer.position = localCenter
        wheelLayer.opacity = 0
        contentLayer.addSublayer(wheelLayer)

        let count = actions.count
        let step: CGFloat = 360 / CGFloat(max(count, 1))
        for (i, action) in actions.enumerated() {
            let centerDeg = 90 - CGFloat(i) * step          // 首项在正上方，顺时针排列
            let shape = CAShapeLayer()
            shape.path = sectorPath(centerDeg: centerDeg, half: step / 2, outer: r1)
            shape.fillColor = NSColor.black.withAlphaComponent(0.45).cgColor  // 半透明甜甜圈：够深以稳定衬托文字
            shape.strokeColor = NSColor.white.withAlphaComponent(0.12).cgColor
            shape.lineWidth = 1
            wheelLayer.addSublayer(shape)

            // 扇区之间的发丝分隔线
            let divider = CAShapeLayer()
            divider.path = boundaryLine(deg: centerDeg - step / 2)
            divider.strokeColor = NSColor.white.withAlphaComponent(0.12).cgColor
            divider.lineWidth = 1
            wheelLayer.addSublayer(divider)

            // 标签（图标 + 文字）
            let rm = (r0 + r1) / 2
            let a = centerDeg * .pi / 180
            let lp = CGPoint(x: localCenter.x + rm * cos(a), y: localCenter.y + rm * sin(a))
            let label = CALayer()
            label.bounds = CGRect(x: 0, y: 0, width: 92, height: 54)
            label.position = lp

            let normalIcon = symbolImage(action.radialSymbolName, color: .white)
            let selectedIcon = symbolImage(action.radialSymbolName, color: .white)
            let icon = CALayer()
            icon.contents = normalIcon
            icon.contentsGravity = .resizeAspect
            icon.frame = CGRect(x: 34, y: 28, width: 24, height: 24)
            label.addSublayer(icon)

            let title = makeText(action.title, size: 12, weight: .medium, color: .white)
            title.frame = CGRect(x: 4, y: 4, width: 84, height: 18)
            label.addSublayer(title)

            wheelLayer.addSublayer(label)

            sectors.append(Sector(action: action, centerDeg: centerDeg, shape: shape,
                                  label: label, icon: icon, title: title, labelBase: lp,
                                  normalIcon: normalIcon, selectedIcon: selectedIcon))
        }

        buildHub()
        buildProgressRing()
    }

    private func buildHub() {
        let hub = CAShapeLayer()
        hub.path = CGPath(ellipseIn: CGRect(x: localCenter.x - r0, y: localCenter.y - r0,
                                            width: r0 * 2, height: r0 * 2), transform: nil)
        hub.fillColor = NSColor.black.withAlphaComponent(0.18).cgColor
        hub.strokeColor = NSColor.white.withAlphaComponent(0.16).cgColor
        hub.lineWidth = 1
        wheelLayer.addSublayer(hub)

        let hubIcon = CALayer()
        hubIcon.contents = symbolImage("cursorarrow", color: accent)
        hubIcon.contentsGravity = .resizeAspect
        hubIcon.frame = CGRect(x: localCenter.x - 11, y: localCenter.y + 6, width: 22, height: 22)
        wheelLayer.addSublayer(hubIcon)

        hubTitle = makeText("移动鼠标", size: 13, weight: .semibold,
                            color: NSColor.white.withAlphaComponent(0.92))
        hubTitle.frame = CGRect(x: localCenter.x - 44, y: localCenter.y - 12, width: 88, height: 18)
        wheelLayer.addSublayer(hubTitle)

        hubSub = makeText("选择动作", size: 10.5, weight: .regular,
                          color: NSColor.white.withAlphaComponent(0.45))
        hubSub.frame = CGRect(x: localCenter.x - 44, y: localCenter.y - 28, width: 88, height: 14)
        wheelLayer.addSublayer(hubSub)
    }

    private func buildProgressRing() {
        let pr: CGFloat = 15
        let ringRect = CGRect(x: localCenter.x - pr, y: localCenter.y - pr, width: pr * 2, height: pr * 2)

        // 空心细环底轨（无填充，透出桌面）
        progressTrack.path = CGPath(ellipseIn: ringRect, transform: nil)
        progressTrack.fillColor = NSColor.clear.cgColor
        progressTrack.strokeColor = NSColor.white.withAlphaComponent(0.22).cgColor
        progressTrack.lineWidth = 2.5
        contentLayer.addSublayer(progressTrack)

        // 从正上方顺时针填充
        let arc = CGMutablePath()
        arc.addArc(center: localCenter, radius: pr, startAngle: .pi / 2,
                   endAngle: .pi / 2 - 2 * .pi, clockwise: true)
        progressRing.path = arc
        progressRing.fillColor = NSColor.clear.cgColor
        progressRing.strokeColor = accent.cgColor
        progressRing.lineWidth = 2.5
        progressRing.lineCap = .round
        progressRing.strokeEnd = 0
        contentLayer.addSublayer(progressRing)
    }

    // MARK: Lifecycle animations

    func startProgress(duration: TimeInterval) {
        let anim = CABasicAnimation(keyPath: "strokeEnd")
        anim.fromValue = 0
        anim.toValue = 1
        anim.duration = duration
        anim.timingFunction = CAMediaTimingFunction(name: .linear)
        anim.fillMode = .forwards
        anim.isRemovedOnCompletion = false
        progressRing.strokeEnd = 1
        progressRing.add(anim, forKey: "progress")
    }

    func bloom() {
        guard !bloomed else { return }
        bloomed = true

        // 进度环淡出
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.14)
        progressRing.opacity = 0
        progressTrack.opacity = 0
        CATransaction.commit()

        // 轮盘绽放：透明度 + 弹簧缩放
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.16
        fade.fillMode = .forwards
        wheelLayer.opacity = 1
        wheelLayer.add(fade, forKey: "fade")

        let scale = CASpringAnimation(keyPath: "transform.scale")
        scale.damping = 13
        scale.stiffness = 260
        scale.mass = 1
        scale.fromValue = 0.82
        scale.toValue = 1
        scale.duration = scale.settlingDuration
        wheelLayer.add(scale, forKey: "appear")
    }

    // MARK: Interaction

    func update(cursor: CGPoint) {
        guard bloomed else { return }
        let dx = cursor.x - center.x
        let dy = cursor.y - center.y
        let dist = hypot(dx, dy)
        if dist < r0 {
            apply(selection: -1)
            return
        }
        let ang = atan2(dy, dx) * 180 / .pi
        var best = 0
        var bestDelta: CGFloat = 999
        for (i, s) in sectors.enumerated() {
            var d = abs((ang - s.centerDeg).truncatingRemainder(dividingBy: 360))
            if d > 180 { d = 360 - d }
            if d < bestDelta { bestDelta = d; best = i }
        }
        apply(selection: best)
    }

    func selectedAction() -> CaptureAction? {
        guard selectedIndex >= 0 && selectedIndex < sectors.count else { return nil }
        return sectors[selectedIndex].action
    }

    private func apply(selection newIndex: Int) {
        guard newIndex != selectedIndex else { return }
        let previous = selectedIndex
        selectedIndex = newIndex

        CATransaction.begin()
        CATransaction.setAnimationDuration(0.16)
        if previous >= 0 { setSector(previous, selected: false) }
        if newIndex >= 0 { setSector(newIndex, selected: true) }
        CATransaction.commit()

        if newIndex >= 0 {
            hubTitle.string = sectors[newIndex].action.title
            hubSub.string = sectors[newIndex].action.detail
        } else {
            hubTitle.string = "移动鼠标"
            hubSub.string = "选择动作"
        }
    }

    private func setSector(_ i: Int, selected: Bool) {
        let s = sectors[i]
        // 选中用主题色作扇区填充，图标/文字始终白色 —— 无论主题色深浅都保证对比。
        s.shape.fillColor = (selected ? accent.withAlphaComponent(0.85)
                                      : NSColor.black.withAlphaComponent(0.45)).cgColor
        s.shape.strokeColor = (selected ? accent.withAlphaComponent(0.95)
                                        : NSColor.white.withAlphaComponent(0.12)).cgColor
        s.icon.contents = selected ? s.selectedIcon : s.normalIcon
        s.title.foregroundColor = NSColor.white.cgColor

        // 果冻形变：外缘半径用弹簧动画过冲回弹
        let step: CGFloat = 360 / CGFloat(sectors.count)
        let targetOuter = selected ? r1 + bulge : r1
        let targetPath = sectorPath(centerDeg: s.centerDeg, half: step / 2, outer: targetOuter)
        let spring = CASpringAnimation(keyPath: "path")
        spring.damping = 11
        spring.stiffness = 320
        spring.mass = 1
        spring.initialVelocity = 6
        spring.duration = spring.settlingDuration
        spring.fromValue = s.shape.presentation()?.path ?? s.shape.path
        spring.toValue = targetPath
        s.shape.path = targetPath
        s.shape.add(spring, forKey: "jelly")

        // 标签跟随微微外移，强化弹性
        let a = s.centerDeg * .pi / 180
        let push: CGFloat = selected ? 6 : 0
        let target = CGPoint(x: s.labelBase.x + push * cos(a), y: s.labelBase.y + push * sin(a))
        let move = CASpringAnimation(keyPath: "position")
        move.damping = 12
        move.stiffness = 320
        move.mass = 1
        move.duration = move.settlingDuration
        move.fromValue = s.label.presentation()?.position ?? s.label.position
        move.toValue = target
        s.label.position = target
        s.label.add(move, forKey: "labelJelly")
    }

    // MARK: Geometry helpers

    private func sectorPath(centerDeg: CGFloat, half: CGFloat, outer: CGFloat) -> CGPath {
        let a0 = (centerDeg - half) * .pi / 180
        let a1 = (centerDeg + half) * .pi / 180
        let c = localCenter
        let path = CGMutablePath()
        path.move(to: CGPoint(x: c.x + r0 * cos(a0), y: c.y + r0 * sin(a0)))
        path.addLine(to: CGPoint(x: c.x + outer * cos(a0), y: c.y + outer * sin(a0)))
        path.addArc(center: c, radius: outer, startAngle: a0, endAngle: a1, clockwise: false)
        path.addLine(to: CGPoint(x: c.x + r0 * cos(a1), y: c.y + r0 * sin(a1)))
        path.addArc(center: c, radius: r0, startAngle: a1, endAngle: a0, clockwise: true)
        path.closeSubpath()
        return path
    }

    private func boundaryLine(deg: CGFloat) -> CGPath {
        let a = deg * .pi / 180
        let c = localCenter
        let path = CGMutablePath()
        path.move(to: CGPoint(x: c.x + r0 * cos(a), y: c.y + r0 * sin(a)))
        path.addLine(to: CGPoint(x: c.x + r1 * cos(a), y: c.y + r1 * sin(a)))
        return path
    }

    private func makeText(_ string: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> CATextLayer {
        let text = CATextLayer()
        text.string = string
        text.font = NSFont.systemFont(ofSize: size, weight: weight)
        text.fontSize = size
        text.foregroundColor = color.cgColor
        text.alignmentMode = .center
        text.truncationMode = .none
        text.contentsScale = backingScale
        return text
    }

    private func symbolImage(_ name: String, color: NSColor) -> CGImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return nil }
        let size = base.size
        let tinted = NSImage(size: size)
        tinted.lockFocus()
        color.set()
        let rect = NSRect(origin: .zero, size: size)
        base.draw(in: rect)
        rect.fill(using: .sourceAtop)
        tinted.unlockFocus()
        var proposed = CGRect(origin: .zero, size: size)
        return tinted.cgImage(forProposedRect: &proposed, context: nil, hints: nil)
    }
}

private extension CaptureAction {
    var radialSymbolName: String {
        switch self {
        case .screenshotCopy: return "camera"
        case .screenshotSave: return "square.and.arrow.down"
        case .screenshotSaveAndCopy: return "square.and.arrow.down.on.square"
        case .ocrCopy: return "text.viewfinder"
        case .pickColor: return "eyedropper"
        }
    }
}
