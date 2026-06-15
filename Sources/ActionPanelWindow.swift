import AppKit

final class ActionPanelWindow: NSWindow {
    private let settings = AppSettings.shared
    private let onSelect: (CaptureAction) -> Void
    private let onSettings: () -> Void

    init(onSelect: @escaping (CaptureAction) -> Void, onSettings: @escaping () -> Void) {
        self.onSelect = onSelect
        self.onSettings = onSettings
        super.init(
            contentRect: CGRect(x: 0, y: 0, width: 420, height: 360),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        title = "Intent Capture"
        minSize = CGSize(width: 420, height: 360)
        isReleasedWhenClosed = false
        setFrameAutosaveName("IntentCaptureHome")
        level = .normal
        hasShadow = true
        contentView = ActionPanelView(settings: settings, onSelect: { [weak self] action in
            self?.close()
            onSelect(action)
        }, onSettings: onSettings)
    }

    func showMainWindow() {
        if !isVisible {
            center()
        }
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

final class ActionPanelView: NSView {
    private let settings: AppSettings
    private let onSelect: (CaptureAction) -> Void
    private let onSettings: () -> Void

    init(settings: AppSettings, onSelect: @escaping (CaptureAction) -> Void, onSettings: @escaping () -> Void) {
        self.settings = settings
        self.onSelect = onSelect
        self.onSettings = onSettings
        super.init(frame: CGRect(x: 0, y: 0, width: 420, height: 360))
        wantsLayer = true
        build()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
    }

    private func build() {
        let title = label("选择默认动作", size: 18, weight: .semibold, color: .labelColor)
        title.frame = CGRect(x: 24, y: 306, width: 220, height: 28)
        addSubview(title)

        let subtitle = label("选中后会成为快捷键和滚轮短按的默认动作", size: 12, weight: .regular, color: .secondaryLabelColor)
        subtitle.frame = CGRect(x: 24, y: 282, width: 320, height: 20)
        addSubview(subtitle)

        let settingsButton = NSButton(title: "设置", target: self, action: #selector(openSettings))
        settingsButton.bezelStyle = .rounded
        settingsButton.frame = CGRect(x: 326, y: 304, width: 70, height: 28)
        addSubview(settingsButton)

        for (index, action) in CaptureAction.allCases.enumerated() {
            let button = ActionChoiceButton(action: action, current: action == settings.recentAction)
            button.frame = CGRect(x: 24, y: 218 - index * 44, width: 372, height: 34)
            button.target = self
            button.action = #selector(selectAction(_:))
            addSubview(button)
        }
    }

    @objc private func selectAction(_ sender: ActionChoiceButton) {
        onSelect(sender.actionValue)
    }

    @objc private func openSettings() {
        onSettings()
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        return field
    }
}

final class ActionChoiceButton: NSButton {
    let actionValue: CaptureAction
    private let current: Bool

    init(action: CaptureAction, current: Bool) {
        self.actionValue = action
        self.current = current
        super.init(frame: .zero)
        title = ""
        isBordered = false
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8)
        (current ? NSColor(calibratedRed: 0.18, green: 0.65, blue: 0.78, alpha: 0.14) : NSColor.controlBackgroundColor.withAlphaComponent(0.72)).setFill()
        path.fill()
        (current ? NSColor(calibratedRed: 0.18, green: 0.65, blue: 0.78, alpha: 0.32) : NSColor.separatorColor).setStroke()
        path.stroke()

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        NSString(string: actionValue.title).draw(in: CGRect(x: 14, y: 9, width: 100, height: 18), withAttributes: titleAttrs)

        let detailAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        NSString(string: actionValue.detail).draw(in: CGRect(x: 128, y: 10, width: 190, height: 16), withAttributes: detailAttrs)

        if current {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor(calibratedRed: 0.18, green: 0.65, blue: 0.78, alpha: 1)
            ]
            NSString(string: "当前").draw(in: CGRect(x: bounds.width - 50, y: 10, width: 34, height: 16), withAttributes: attrs)
        }
    }
}
