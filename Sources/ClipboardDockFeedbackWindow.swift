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
    init(message: String, tone: ClipboardDockFeedbackTone, anchor: CGPoint) {
        let size = CGSize(width: 208, height: 38)
        let screen = NSScreen.screens.first { $0.frame.contains(anchor) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
        let x = min(max(anchor.x - size.width / 2, visible.minX + 10), visible.maxX - size.width - 10)
        let y = min(max(anchor.y + 8, visible.minY + 10), visible.maxY - size.height - 10)

        super.init(
            contentRect: CGRect(x: x, y: y, width: size.width, height: size.height),
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
        contentView = ClipboardDockFeedbackView(message: message, tone: tone)
    }
}

final class ClipboardDockFeedbackView: NSView {
    private let message: String
    private let tone: ClipboardDockFeedbackTone

    init(message: String, tone: ClipboardDockFeedbackTone) {
        self.message = message
        self.tone = tone
        super.init(frame: CGRect(x: 0, y: 0, width: 208, height: 38))
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        let card = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 11, yRadius: 11)
        NSColor.windowBackgroundColor.withAlphaComponent(0.94).setFill()
        card.fill()
        tone.color.withAlphaComponent(0.80).setStroke()
        card.lineWidth = 1.2
        card.stroke()

        let symbol = NSImage(systemSymbolName: tone.symbolName, accessibilityDescription: nil)
        symbol?.draw(in: CGRect(x: 12, y: 10, width: 18, height: 18))
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        NSString(string: message).draw(in: CGRect(x: 38, y: 11, width: 158, height: 17), withAttributes: attrs)
    }
}

enum ClipboardDockFeedback {
    private static var current: ClipboardDockFeedbackWindow?

    static func show(message: String, tone: ClipboardDockFeedbackTone, anchor: CGPoint) {
        current?.close()
        let window = ClipboardDockFeedbackWindow(message: message, tone: tone, anchor: anchor)
        current = window
        window.alphaValue = 0
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.10
            window.animator().alphaValue = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            guard current === window else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.16
                window.animator().alphaValue = 0
            }, completionHandler: {
                if current === window {
                    window.close()
                    current = nil
                }
            })
        }
    }
}
