import AppKit

// 语气/颜色/图标统一走 Design.swift 的 FeedbackTone（与主 Toast 同一真相源）。

final class ClipboardDockFeedbackWindow: NSPanel {
    static let toastHeight: CGFloat = 40

    init(message: String, tone: FeedbackTone) {
        let width = ClipboardDockFeedbackView.preferredWidth(for: message)
        super.init(
            contentRect: CGRect(x: 0, y: 0, width: width, height: Self.toastHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .mainMenu
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        contentView = ClipboardDockFeedbackView(
            message: message,
            tone: tone,
            frame: CGRect(x: 0, y: 0, width: width, height: Self.toastHeight)
        )
    }
}

final class ClipboardDockFeedbackView: NSView {
    private static let font = NSFont.systemFont(ofSize: 12.5, weight: .semibold)

    static func preferredWidth(for message: String) -> CGFloat {
        let textWidth = (message as NSString).size(withAttributes: [.font: font]).width
        return min(max(textWidth + 58, 150), 320)
    }

    init(message: String, tone: FeedbackTone, frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        // 毛玻璃胶囊底 + 色调描边，比原来纯色卡片更精致。
        let blur = NSVisualEffectView(frame: bounds)
        blur.autoresizingMask = [.width, .height]
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = frame.height / 2
        blur.layer?.masksToBounds = true
        blur.layer?.borderWidth = 1
        blur.layer?.borderColor = tone.color.withAlphaComponent(0.55).cgColor
        addSubview(blur)

        let icon = NSImageView(frame: CGRect(x: 13, y: (frame.height - 19) / 2, width: 19, height: 19))
        icon.image = NSImage(systemSymbolName: tone.symbolName, accessibilityDescription: nil)
        icon.contentTintColor = tone.color
        icon.imageScaling = .scaleProportionallyUpOrDown
        addSubview(icon)

        let label = NSTextField(labelWithString: message)
        label.font = Self.font
        label.textColor = .labelColor
        label.backgroundColor = .clear
        label.isBordered = false
        label.alignment = .left
        label.cell?.usesSingleLineMode = true
        label.lineBreakMode = .byTruncatingTail
        label.frame = CGRect(x: 40, y: (frame.height - 17) / 2, width: frame.width - 52, height: 17)
        addSubview(label)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// 贴近 Dock 的操作反馈。多条会**向上堆叠**，避免横向铺开过长。
enum ClipboardDockFeedback {
    private static var stack: [ClipboardDockFeedbackWindow] = []
    private static var baseAnchor: CGPoint?
    private static let pileOffset: CGFloat = 9      // 每层小偏移，堆成一叠而非铺开
    private static let lifetime: TimeInterval = 1.6

    static func show(message: String, tone: FeedbackTone, anchor: CGPoint) {
        if stack.isEmpty { baseAnchor = anchor }
        let window = ClipboardDockFeedbackWindow(message: message, tone: tone)
        window.alphaValue = 0
        stack.append(window)
        window.orderFrontRegardless()
        restack()                       // 由 restack 统一把新窗从 0 淡入到目标透明度
        DispatchQueue.main.asyncAfter(deadline: .now() + lifetime) {
            dismiss(window)
        }
    }

    private static func dismiss(_ window: ClipboardDockFeedbackWindow) {
        guard let index = stack.firstIndex(where: { $0 === window }) else { return }
        stack.remove(at: index)
        if stack.isEmpty { baseAnchor = nil }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.16
            window.animator().alphaValue = 0
        }, completionHandler: {
            window.close()
        })
        restack()
    }

    // 紧凑堆叠：最新的在最前（贴近 anchor、最实），越旧越往上错开一点、越淡，像一叠卡片。
    private static func restack() {
        guard let base = baseAnchor else { return }
        let height = ClipboardDockFeedbackWindow.toastHeight
        let screen = NSScreen.screens.first { $0.frame.contains(base) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
        let count = stack.count
        for (i, window) in stack.enumerated() {
            let depth = count - 1 - i    // 最新(末尾)=0 在最前
            let width = window.frame.width
            let x = min(max(base.x - width / 2, visible.minX + 10), visible.maxX - width - 10)
            let y = min(base.y + 8 + CGFloat(depth) * pileOffset, visible.maxY - height - 10)
            let alpha: CGFloat = depth == 0 ? 1 : max(0.28, 1 - CGFloat(depth) * 0.26)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().setFrame(CGRect(x: x, y: y, width: width, height: height), display: true)
                window.animator().alphaValue = alpha
            }
        }
    }
}
