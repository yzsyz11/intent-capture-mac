import AppKit

enum ClipboardDockFeedbackTone {
    case success
    case info
    case destructive

    var color: NSColor {
        switch self {
        case .success: return .systemGreen
        case .info: return .systemBlue
        case .destructive: return .systemRed
        }
    }

    var symbolName: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .info: return "info.circle.fill"
        case .destructive: return "trash.circle.fill"
        }
    }
}

final class ClipboardDockFeedbackWindow: NSPanel {
    static let toastHeight: CGFloat = 40

    init(message: String, tone: ClipboardDockFeedbackTone) {
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

    init(message: String, tone: ClipboardDockFeedbackTone, frame: NSRect) {
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
    private static let gap: CGFloat = 8
    private static let lifetime: TimeInterval = 1.6

    static func show(message: String, tone: ClipboardDockFeedbackTone, anchor: CGPoint) {
        if stack.isEmpty { baseAnchor = anchor }
        let window = ClipboardDockFeedbackWindow(message: message, tone: tone)
        stack.append(window)
        window.alphaValue = 0
        window.orderFrontRegardless()
        restack()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            window.animator().alphaValue = 1
        }
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

    // 从 baseAnchor 起向上堆叠，最新的在最上。
    private static func restack() {
        guard let base = baseAnchor else { return }
        let height = ClipboardDockFeedbackWindow.toastHeight
        let screen = NSScreen.screens.first { $0.frame.contains(base) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
        for (i, window) in stack.enumerated() {
            let width = window.frame.width
            let x = min(max(base.x - width / 2, visible.minX + 10), visible.maxX - width - 10)
            let y = min(base.y + 8 + CGFloat(i) * (height + gap), visible.maxY - height - 10)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().setFrame(CGRect(x: x, y: y, width: width, height: height), display: true)
            }
        }
    }
}
