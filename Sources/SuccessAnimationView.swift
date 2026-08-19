import AppKit
import QuartzCore

/// 「成功」动效：先转一小圈 loading，再自然过渡到绿色打勾。
/// 快但有——总时长 ~0.5s。可复用于剪贴板卡片点击复制、截图成功提示等处。
///
/// 过渡设计（自然衔接，不是硬切）：
///   1. 主题色圆弧转一圈（spin）
///   2. 圆弧补成整圈并转绿（complete）
///   3. 绿色对号自己描出来（check）
///   4. 短暂停留后回调（hold）
final class SuccessAnimationView: NSView {
    // 时长常量，集中在此便于调手感。
    private let spinDuration: CFTimeInterval = 0.30
    private let completeDuration: CFTimeInterval = 0.16
    private let checkDuration: CFTimeInterval = 0.18
    private let holdDuration: CFTimeInterval = 0.08

    private let disc = CAShapeLayer()
    private let ring = CAShapeLayer()
    private let check = CAShapeLayer()
    private let accent: NSColor
    private let success: NSColor
    private var isPlaying = false

    init(diameter: CGFloat, accent: NSColor, success: NSColor = .systemGreen) {
        self.accent = accent
        self.success = success
        super.init(frame: CGRect(x: 0, y: 0, width: diameter, height: diameter))
        wantsLayer = true
        configureLayers(diameter: diameter)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureLayers(diameter d: CGFloat) {
        let center = CGPoint(x: d / 2, y: d / 2)
        let radius = d * 0.40
        let lineWidth = max(2, d * 0.08)

        // 背衬暗圆，保证在任意卡片内容（含图片）上都读得清。
        disc.path = CGPath(ellipseIn: bounds, transform: nil)
        disc.fillColor = NSColor.black.withAlphaComponent(0.32).cgColor
        layer?.addSublayer(disc)

        let ringPath = CGMutablePath()
        ringPath.addArc(center: center, radius: radius, startAngle: .pi / 2, endAngle: .pi / 2 - 2 * .pi, clockwise: true)
        ring.path = ringPath
        ring.fillColor = NSColor.clear.cgColor
        ring.strokeColor = accent.cgColor
        ring.lineWidth = lineWidth
        ring.lineCap = .round
        withoutImplicitAnimation { ring.strokeEnd = 0.28 }
        layer?.addSublayer(ring)

        // 对号路径（y 向上坐标）。
        let checkPath = CGMutablePath()
        checkPath.move(to: CGPoint(x: d * 0.30, y: d * 0.50))
        checkPath.addLine(to: CGPoint(x: d * 0.44, y: d * 0.35))
        checkPath.addLine(to: CGPoint(x: d * 0.72, y: d * 0.66))
        check.path = checkPath
        check.fillColor = NSColor.clear.cgColor
        check.strokeColor = success.cgColor
        check.lineWidth = lineWidth
        check.lineCap = .round
        check.lineJoin = .round
        withoutImplicitAnimation { check.strokeEnd = 0 }
        layer?.addSublayer(check)
    }

    /// 播放一次；动画自然结束后回调。重复调用忽略。
    func play(completion: (() -> Void)? = nil) {
        guard !isPlaying else { return }
        isPlaying = true

        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = -2 * Double.pi
        spin.duration = spinDuration
        spin.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        ring.add(spin, forKey: "spin")

        DispatchQueue.main.asyncAfter(deadline: .now() + spinDuration) { [weak self] in
            self?.completeRingThenCheck(completion: completion)
        }
    }

    private func completeRingThenCheck(completion: (() -> Void)?) {
        ring.removeAnimation(forKey: "spin")
        CATransaction.begin()
        CATransaction.setAnimationDuration(completeDuration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        ring.strokeEnd = 1
        ring.strokeColor = success.cgColor
        CATransaction.commit()

        DispatchQueue.main.asyncAfter(deadline: .now() + completeDuration) { [weak self] in
            guard let self else { return }
            let draw = CABasicAnimation(keyPath: "strokeEnd")
            draw.fromValue = 0
            draw.toValue = 1
            draw.duration = self.checkDuration
            draw.timingFunction = CAMediaTimingFunction(name: .easeOut)
            draw.fillMode = .forwards
            draw.isRemovedOnCompletion = false
            self.check.strokeEnd = 1
            self.check.add(draw, forKey: "draw")

            DispatchQueue.main.asyncAfter(deadline: .now() + self.checkDuration + self.holdDuration) {
                completion?()
            }
        }
    }

    private func withoutImplicitAnimation(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
    }
}
