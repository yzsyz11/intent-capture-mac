import AppKit
import ApplicationServices

enum HomeSection: CaseIterable {
    case action, hotkeys, clipboard, mouse, translation, appearance, saving

    var title: String {
        switch self {
        case .action: return "默认动作"
        case .hotkeys: return "快捷键"
        case .clipboard: return "剪贴板拓展坞"
        case .mouse: return "鼠标中键"
        case .translation: return "翻译"
        case .appearance: return "外观"
        case .saving: return "默认与保存"
        }
    }

    var symbolName: String {
        switch self {
        case .action: return "target"
        case .hotkeys: return "keyboard"
        case .clipboard: return "clipboard"
        case .mouse: return "computermouse"
        case .translation: return "character.bubble"
        case .appearance: return "paintpalette"
        case .saving: return "folder"
        }
    }
}

/// 主页 + 设置合并成的单窗口：左侧玻璃侧边栏导航，右侧内容区随选中分区切换。
final class HomeWindow: NSWindow {
    private let homeView: HomeWindowView

    init(onSelectAction: @escaping (CaptureAction) -> Void, onSettingsSaved: @escaping () -> Void) {
        homeView = HomeWindowView(
            settings: AppSettings.shared,
            onSelectAction: onSelectAction,
            onSettingsSaved: onSettingsSaved
        )
        super.init(
            contentRect: CGRect(x: 0, y: 0, width: 680, height: 420),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        title = "Intent Capture"
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        appearance = NSAppearance(named: .aqua) // 白底重构：锁浅色，系统深色下也保持白
        contentView = homeView
    }

    func showMainWindow(section: HomeSection = .action) {
        homeView.select(section)
        if !isVisible {
            center()
        }
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func refreshPermissionStatus() {
        homeView.refreshPermissionStatus()
    }
}

final class HomeWindowView: NSView {
    private let onSelectAction: (CaptureAction) -> Void
    private let backgroundEffect = NSVisualEffectView()
    private let sidebar = SidebarView()
    private let actionSection: ActionSectionView
    private let hotkeySection: HotkeySectionView
    private let clipboardSection: ClipboardSectionView
    private let mouseSection: MouseSectionView
    private let translationSection: TranslationSectionView
    private let appearanceSection: AppearanceSectionView
    private let saveSection: SaveSectionView
    private var sections: [HomeSection: NSView] = [:]

    override var isFlipped: Bool { true }

    init(settings: AppSettings, onSelectAction: @escaping (CaptureAction) -> Void, onSettingsSaved: @escaping () -> Void) {
        self.onSelectAction = onSelectAction
        actionSection = ActionSectionView(settings: settings)
        hotkeySection = HotkeySectionView(settings: settings, onSave: onSettingsSaved)
        clipboardSection = ClipboardSectionView(settings: settings, onSave: onSettingsSaved)
        mouseSection = MouseSectionView(settings: settings, onSave: onSettingsSaved)
        translationSection = TranslationSectionView(settings: settings, onSave: onSettingsSaved)
        appearanceSection = AppearanceSectionView(settings: settings)
        saveSection = SaveSectionView(settings: settings, onSave: onSettingsSaved, onActionChanged: {})
        super.init(frame: CGRect(x: 0, y: 0, width: 680, height: 420))
        wantsLayer = true
        saveSection.onActionChanged = { [weak self] in self?.actionSection.reloadCurrent() }
        appearanceSection.onAccentChanged = { [weak self] in self?.refreshAccent() }
        build()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func build() {
        // 白底重构：改实心白背景，替代原来盖在桌面壁纸上的半透明磨砂（会让整个 app 发暗）。
        wantsLayer = true
        layer?.backgroundColor = Design.Color.cardFill.cgColor
        backgroundEffect.isHidden = true
        backgroundEffect.autoresizingMask = [.width, .height]
        backgroundEffect.frame = bounds
        addSubview(backgroundEffect)

        sidebar.frame = CGRect(x: 0, y: 0, width: 188, height: bounds.height)
        sidebar.autoresizingMask = [.height]
        sidebar.onSelect = { [weak self] section in self?.select(section) }
        addSubview(sidebar)

        sections = [
            .action: actionSection,
            .hotkeys: hotkeySection,
            .clipboard: clipboardSection,
            .mouse: mouseSection,
            .translation: translationSection,
            .appearance: appearanceSection,
            .saving: saveSection
        ]
        actionSection.onSelect = { [weak self] action in self?.onSelectAction(action) }

        for (_, view) in sections {
            view.frame = CGRect(x: 188, y: 0, width: bounds.width - 188, height: bounds.height)
            view.autoresizingMask = [.width, .height]
            view.isHidden = true
            addSubview(view)
        }
        select(.action)
    }

    func select(_ section: HomeSection) {
        sidebar.setActive(section)
        for (key, view) in sections {
            view.isHidden = key != section
        }
    }

    func refreshPermissionStatus() {
        mouseSection.refreshPermissionStatus()
    }

    /// 主题色改变后，强制重绘所有会用到强调色的视图。
    private func refreshAccent() {
        func redraw(_ view: NSView) {
            view.needsDisplay = true
            view.subviews.forEach(redraw)
        }
        redraw(sidebar)
        sections.values.forEach(redraw)
    }
}

// MARK: - Sidebar

final class SidebarView: NSView {
    var onSelect: ((HomeSection) -> Void)?
    private var buttons: [HomeSection: NavItemButton] = [:]

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: CGRect(x: 0, y: 0, width: 188, height: 420))
        wantsLayer = true
        build()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.025).setFill()
        bounds.fill()
        let line = NSBezierPath()
        line.move(to: CGPoint(x: bounds.width - 0.5, y: 0))
        line.line(to: CGPoint(x: bounds.width - 0.5, y: bounds.height))
        line.lineWidth = 1
        NSColor.black.withAlphaComponent(0.09).setStroke()
        line.stroke()
    }

    private func build() {
        // Traffic lights occupy the top ~30pt band once the titlebar folds into this
        // view (fullSizeContentView) — nav items start below that clearance.
        var y: CGFloat = 40
        for section in HomeSection.allCases {
            let button = NavItemButton(section: section)
            button.target = self
            button.action = #selector(tap(_:))
            button.frame = CGRect(x: 12, y: y, width: 164, height: 30)
            addSubview(button)
            buttons[section] = button
            y += 34
        }
        setActive(.action)
    }

    @objc private func tap(_ sender: NavItemButton) {
        onSelect?(sender.section)
    }

    func setActive(_ section: HomeSection) {
        buttons.forEach { $0.value.isActive = $0.key == section }
    }
}

final class NavItemButton: NSButton {
    let section: HomeSection
    var isActive: Bool = false { didSet { needsDisplay = true } }
    private var isHovering = false
    private var accent: NSColor { AppSettings.shared.accentColor }

    init(section: HomeSection) {
        self.section = section
        super.init(frame: .zero)
        title = ""
        isBordered = false
        wantsLayer = true
        toolTip = section.title
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10)
        if isActive {
            accent.withAlphaComponent(0.15).setFill()
        } else if isHovering {
            NSColor.black.withAlphaComponent(0.05).setFill()
        } else {
            NSColor.clear.setFill()
        }
        path.fill()
        if isActive {
            path.lineWidth = 1
            accent.withAlphaComponent(0.40).setStroke()
            path.stroke()
        }

        if let symbol = NSImage(systemSymbolName: section.symbolName, accessibilityDescription: nil) {
            let tinted = symbol.tinted(with: isActive ? accent : NSColor.secondaryLabelColor)
            tinted.draw(in: CGRect(x: 10, y: bounds.midY - 8, width: 16, height: 16))
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12.5, weight: isActive ? .semibold : .regular),
            .foregroundColor: isActive ? accent : NSColor.labelColor
        ]
        NSString(string: section.title).draw(at: CGPoint(x: 34, y: bounds.midY - 8), withAttributes: attrs)
    }
}

// MARK: - Action section (former ActionPanelView)

final class ActionSectionView: NSView {
    private let settings: AppSettings
    var onSelect: ((CaptureAction) -> Void)?
    private var buttons: [ActionChoiceButton] = []

    override var isFlipped: Bool { true }

    init(settings: AppSettings) {
        self.settings = settings
        super.init(frame: CGRect(x: 0, y: 0, width: 492, height: 420))
        build()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func build() {
        let title = NSTextField(labelWithString: "选择默认动作")
        title.font = .systemFont(ofSize: 18, weight: .semibold)
        title.textColor = .labelColor
        title.frame = CGRect(x: 28, y: 28, width: 300, height: 26)
        addSubview(title)

        let subtitle = NSTextField(labelWithString: "选中后会成为快捷键和滚轮短按的默认动作")
        subtitle.font = .systemFont(ofSize: 12, weight: .regular)
        subtitle.textColor = .secondaryLabelColor
        subtitle.frame = CGRect(x: 28, y: 60, width: 380, height: 18)
        addSubview(subtitle)

        reloadCurrent()
    }

    func reloadCurrent() {
        buttons.forEach { $0.removeFromSuperview() }
        buttons.removeAll()
        var y: CGFloat = 94
        for action in CaptureAction.allCases {
            let button = ActionChoiceButton(action: action, current: action == settings.recentAction)
            button.frame = CGRect(x: 28, y: y, width: 420, height: 40)
            button.target = self
            button.action = #selector(tap(_:))
            addSubview(button)
            buttons.append(button)
            y += 48
        }
    }

    @objc private func tap(_ sender: ActionChoiceButton) {
        onSelect?(sender.actionValue)
    }
}

final class ActionChoiceButton: NSButton {
    let actionValue: CaptureAction
    private let current: Bool
    private var isHovering = false

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

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 12, yRadius: 12)
        let accent = AppSettings.shared.accentColor
        if current {
            accent.withAlphaComponent(0.12).setFill()
        } else {
            NSColor.white.withAlphaComponent(isHovering ? 0.16 : 0.10).setFill()
        }
        path.fill()
        (current ? accent.withAlphaComponent(0.40) : NSColor.white.withAlphaComponent(isHovering ? 0.46 : 0.30)).setStroke()
        path.lineWidth = 1
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
                .foregroundColor: AppSettings.shared.accentColor
            ]
            NSString(string: "当前").draw(in: CGRect(x: bounds.width - 50, y: 10, width: 34, height: 16), withAttributes: attrs)
        }
    }
}

// MARK: - Settings sections (former SettingsView, split by sidebar tab)

@discardableResult
private func placeRow(in parent: NSView, title: String, control: NSView, y: CGFloat, width: CGFloat, height: CGFloat = 28) -> CGFloat {
    let label = NSTextField(labelWithString: title)
    label.font = .systemFont(ofSize: 12)
    label.textColor = .secondaryLabelColor
    label.frame = CGRect(x: 16, y: y + (height - 16) / 2, width: 120, height: 16)
    parent.addSubview(label)
    control.frame = CGRect(x: 152, y: y, width: width - 152 - 16, height: height)
    parent.addSubview(control)
    return y + height + 12
}

private func sectionTitle(_ text: String, in parent: NSView) {
    let label = NSTextField(labelWithString: text)
    label.font = .systemFont(ofSize: 14, weight: .semibold)
    label.textColor = .labelColor
    label.frame = CGRect(x: 16, y: 16, width: 200, height: 20)
    parent.addSubview(label)
}

final class HotkeySectionView: NSView {
    private let actionHotkey: HotkeyRecorderButton
    private let panelHotkey: HotkeyRecorderButton
    private let clipboardDockHotkey: HotkeyRecorderButton

    override var isFlipped: Bool { true }

    init(settings: AppSettings, onSave: @escaping () -> Void) {
        actionHotkey = HotkeyRecorderButton(hotkey: settings.actionHotkey)
        panelHotkey = HotkeyRecorderButton(hotkey: settings.panelHotkey)
        clipboardDockHotkey = HotkeyRecorderButton(hotkey: settings.clipboardDockHotkey)
        super.init(frame: CGRect(x: 0, y: 0, width: Design.Layout.contentWidth, height: Design.Layout.windowHeight))

        let header = GroupHeader("键盘快捷键")
        let card = SettingsCard()
        for recorder in [actionHotkey, panelHotkey, clipboardDockHotkey] {
            recorder.translatesAutoresizingMaskIntoConstraints = false
            recorder.widthAnchor.constraint(equalToConstant: 150).isActive = true
            recorder.heightAnchor.constraint(equalToConstant: 28).isActive = true
        }
        card.addRow(SettingRow.make(title: "执行默认动作", control: actionHotkey))
        card.addRow(SettingRow.make(title: "打开主页", control: panelHotkey))
        card.addRow(SettingRow.make(title: "剪贴板拓展坞", control: clipboardDockHotkey))
        addSubview(header)
        addSubview(card)
        let inset = Design.Layout.contentInset
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor, constant: inset),
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset + 2),
            card.topAnchor.constraint(equalTo: header.bottomAnchor, constant: Design.Spacing.s),
            card.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            card.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset)
        ])

        actionHotkey.onChange = { hotkey in
            settings.actionHotkey = hotkey
            onSave()
            Toast.show("动作快捷键已更新：\(hotkey.displayText)")
        }
        panelHotkey.onChange = { hotkey in
            settings.panelHotkey = hotkey
            onSave()
            Toast.show("主页快捷键已更新：\(hotkey.displayText)")
        }
        clipboardDockHotkey.onChange = { hotkey in
            settings.clipboardDockHotkey = hotkey
            onSave()
            Toast.show("剪贴板快捷键已更新：\(hotkey.displayText)")
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// App 风格滑动开关：关=白底灰钮，开=主题色底白钮，圆角胶囊 + 滑动动画。
/// 规格参考用户给的 CSS（3.5:2 比例、圆钮、0.4s 过渡），开态颜色取全局强调色。
final class GlassSwitch: NSControl {
    private let track = CALayer()
    private let knob = CALayer()
    private var accent: NSColor { AppSettings.shared.accentColor }
    private let offColor = NSColor(hexString: "#ADB5BD") ?? .systemGray

    private let trackW: CGFloat = 46
    private let trackH: CGFloat = 26
    private let inset: CGFloat = 4
    private var knobSize: CGFloat { trackH - inset * 2 }

    private(set) var isOn = false

    override init(frame frameRect: NSRect) {
        super.init(frame: CGRect(origin: frameRect.origin, size: NSSize(width: 46, height: 26)))
        wantsLayer = true
        track.frame = CGRect(x: 0, y: 0, width: trackW, height: trackH)
        track.cornerRadius = trackH / 2
        track.borderWidth = 1
        knob.frame = CGRect(x: inset, y: inset, width: knobSize, height: knobSize)
        knob.cornerRadius = knobSize / 2
        track.addSublayer(knob)
        layer?.addSublayer(track)
        updateAppearance(animated: false)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: trackW, height: trackH) }
    override var acceptsFirstResponder: Bool { true }

    func setOn(_ on: Bool, animated: Bool) {
        isOn = on
        updateAppearance(animated: animated)
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    override func mouseDown(with event: NSEvent) {
        setOn(!isOn, animated: true)
        sendAction(action, to: target)
    }

    private func updateAppearance(animated: Bool) {
        let knobX = isOn ? trackW - inset - knobSize : inset
        let trackColor = (isOn ? accent : NSColor.white).cgColor
        let borderColor = (isOn ? accent : offColor).cgColor
        let knobColor = (isOn ? NSColor.white : offColor).cgColor

        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        if animated { CATransaction.setAnimationDuration(0.22) }
        track.backgroundColor = trackColor
        track.borderColor = borderColor
        knob.backgroundColor = knobColor
        knob.frame.origin.x = knobX
        CATransaction.commit()
    }
}

/// 一行「说明文字 + 右侧滑动开关」，替代系统复选框。
final class SwitchRow: NSView {
    let control = GlassSwitch(frame: .zero)
    private let label = NSTextField(labelWithString: "")

    init(title: String, width: CGFloat) {
        super.init(frame: CGRect(x: 16, y: 0, width: width, height: 26))
        label.stringValue = title
        label.font = .systemFont(ofSize: 13)
        label.textColor = .labelColor
        label.frame = CGRect(x: 0, y: 3, width: width - 60, height: 20)
        addSubview(label)
        control.frame = CGRect(x: width - 46, y: 0, width: 46, height: 26)
        addSubview(control)
    }

    required init?(coder: NSCoder) { fatalError() }

    func place(in parent: NSView, y: CGFloat) {
        frame = CGRect(x: 16, y: y, width: frame.width, height: 26)
        parent.addSubview(self)
    }
}

final class ClipboardSectionView: NSView {
    private let toggle = SwitchRow(title: "启用剪贴板历史", width: 404)
    private let card = GlassSectionCard(frame: CGRect(x: 28, y: 28, width: 436, height: 84))
    private let settings: AppSettings
    private let onSave: () -> Void

    override var isFlipped: Bool { true }

    init(settings: AppSettings, onSave: @escaping () -> Void) {
        self.settings = settings
        self.onSave = onSave
        super.init(frame: CGRect(x: 0, y: 0, width: 492, height: 420))
        addSubview(card)
        sectionTitle("剪贴板拓展坞", in: card)

        toggle.control.setOn(settings.clipboardHistoryEnabled, animated: false)
        toggle.control.target = self
        toggle.control.action = #selector(toggleChanged)
        toggle.place(in: card, y: 44)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func toggleChanged() {
        settings.clipboardHistoryEnabled = toggle.control.isOn
        onSave()
        Toast.show(settings.clipboardHistoryEnabled ? "已启用剪贴板历史" : "已关闭剪贴板历史")
    }
}

final class MouseSectionView: NSView {
    private let toggle = SwitchRow(title: "启用鼠标中键触发", width: 404)
    private let statusLabel = NSTextField(labelWithString: "")
    private let requestButton = AccentGhostButton(title: "开启辅助功能权限")
    private let card = GlassSectionCard(frame: CGRect(x: 28, y: 28, width: 436, height: 124))
    private let settings: AppSettings
    private let onSave: () -> Void

    override var isFlipped: Bool { true }

    init(settings: AppSettings, onSave: @escaping () -> Void) {
        self.settings = settings
        self.onSave = onSave
        super.init(frame: CGRect(x: 0, y: 0, width: 492, height: 420))
        addSubview(card)
        sectionTitle("鼠标中键", in: card)

        toggle.control.setOn(settings.middleClickEnabled, animated: false)
        toggle.control.target = self
        toggle.control.action = #selector(toggleChanged)
        toggle.place(in: card, y: 44)

        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.maximumNumberOfLines = 2
        statusLabel.cell?.wraps = true
        statusLabel.frame = CGRect(x: 16, y: 84, width: 254, height: 32)
        card.addSubview(statusLabel)

        requestButton.target = self
        requestButton.action = #selector(requestAccessibility)
        requestButton.frame = CGRect(x: 286, y: 88, width: 134, height: 26)
        card.addSubview(requestButton)

        refreshPermissionStatus()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func toggleChanged() {
        settings.middleClickEnabled = toggle.control.isOn
        onSave()
        refreshPermissionStatus()
        Toast.show(settings.middleClickEnabled ? "已启用鼠标中键触发" : "已关闭鼠标中键触发")
    }

    @objc private func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        settings.middleClickEnabled = true
        toggle.control.setOn(true, animated: true)
        AXIsProcessTrustedWithOptions(options)
        onSave()
        refreshPermissionStatus()
        Toast.show(AXIsProcessTrusted() ? "中键触发已启用" : "授权后请退出并重新打开 Intent Capture。")
    }

    func refreshPermissionStatus() {
        if !settings.middleClickEnabled {
            statusLabel.stringValue = "中键触发已关闭；打开上方开关后才会监听"
        } else if AXIsProcessTrusted() {
            statusLabel.stringValue = "辅助功能权限已生效；中键触发已启用"
        } else {
            statusLabel.stringValue = "辅助功能权限未对当前 App 生效；可能是旧条目或需重启"
        }
    }
}

final class AppearanceSectionView: NSView {
    private let settings: AppSettings
    var onAccentChanged: () -> Void = {}
    private let card = GlassSectionCard(frame: CGRect(x: 28, y: 28, width: 436, height: 176))
    private let colorWell = NSColorWell()
    private var swatches: [AccentSwatchButton] = []
    private let presets = ["#2EA6C7", "#4C8DFF", "#7C6CF0", "#E0567B",
                           "#E8814A", "#E7B93A", "#3FB56B", "#8A8F98"]

    override var isFlipped: Bool { true }

    init(settings: AppSettings) {
        self.settings = settings
        super.init(frame: CGRect(x: 0, y: 0, width: 492, height: 420))
        addSubview(card)
        sectionTitle("外观主题色", in: card)

        let subtitle = NSTextField(labelWithString: "选择强调色，会应用到侧边栏、按钮与中键轮盘")
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor
        subtitle.frame = CGRect(x: 16, y: 44, width: 404, height: 16)
        card.addSubview(subtitle)

        var x: CGFloat = 16
        for hex in presets {
            let swatch = AccentSwatchButton(hex: hex)
            swatch.frame = CGRect(x: x, y: 78, width: 32, height: 32)
            swatch.target = self
            swatch.action = #selector(pickPreset(_:))
            card.addSubview(swatch)
            swatches.append(swatch)
            x += 40
        }

        let customLabel = NSTextField(labelWithString: "自定义")
        customLabel.font = .systemFont(ofSize: 12)
        customLabel.textColor = .secondaryLabelColor
        customLabel.frame = CGRect(x: 16, y: 130, width: 60, height: 16)
        card.addSubview(customLabel)

        colorWell.frame = CGRect(x: 80, y: 124, width: 48, height: 28)
        colorWell.color = settings.accentColor
        colorWell.target = self
        colorWell.action = #selector(pickCustom)
        card.addSubview(colorWell)

        refreshSelection()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // NSColorWell 被点过后会一直处于 active 状态并绑定系统颜色面板，即使关掉设置窗也不解绑；
    // 之后任何一次 NSApp.activate（例如打开图片预览）都会把系统颜色面板重新带到前台。
    // 因此在设置窗关闭时主动解绑并收起颜色面板。
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: nil)
        guard let window else { return }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsWindowWillClose),
            name: NSWindow.willCloseNotification,
            object: window
        )
    }

    @objc private func settingsWindowWillClose() {
        colorWell.deactivate()
        if NSColorPanel.sharedColorPanelExists, NSColorPanel.shared.isVisible {
            NSColorPanel.shared.orderOut(nil)
        }
    }

    @objc private func pickPreset(_ sender: AccentSwatchButton) {
        settings.accentHex = sender.hex
        colorWell.color = settings.accentColor
        onAccentChanged()
        refreshSelection()
        Toast.show("主题色已更新")
    }

    @objc private func pickCustom() {
        settings.accentColor = colorWell.color
        onAccentChanged()
        refreshSelection()
    }

    private func refreshSelection() {
        let current = settings.accentHex.uppercased()
        swatches.forEach { $0.isCurrent = $0.hex.uppercased() == current }
    }
}

/// 主题色预设色板：圆角色块，选中时描一圈白环。
final class AccentSwatchButton: NSButton {
    let hex: String
    var isCurrent = false { didSet { needsDisplay = true } }

    init(hex: String) {
        self.hex = hex
        super.init(frame: .zero)
        title = ""
        isBordered = false
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 3, dy: 3)
        let path = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)
        (NSColor(hexString: hex) ?? .gray).setFill()
        path.fill()
        if isCurrent {
            let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 9, yRadius: 9)
            NSColor.white.withAlphaComponent(0.92).setStroke()
            ring.lineWidth = 2
            ring.stroke()
        }
    }
}

final class SaveSectionView: NSView {
    private let directory = GlassTextField()
    private let defaultAction = NSPopUpButton()
    private let colorFormat = NSPopUpButton()
    private let card = GlassSectionCard(frame: CGRect(x: 28, y: 28, width: 436, height: 172))
    private let settings: AppSettings
    private let onSave: () -> Void
    var onActionChanged: () -> Void

    override var isFlipped: Bool { true }

    init(settings: AppSettings, onSave: @escaping () -> Void, onActionChanged: @escaping () -> Void) {
        self.settings = settings
        self.onSave = onSave
        self.onActionChanged = onActionChanged
        super.init(frame: CGRect(x: 0, y: 0, width: 492, height: 420))
        addSubview(card)
        sectionTitle("默认与保存", in: card)

        directory.stringValue = settings.saveDirectory.path
        directory.target = self
        directory.action = #selector(saveClick)

        defaultAction.addItems(withTitles: CaptureAction.allCases.map(\.title))
        defaultAction.selectItem(withTitle: settings.recentAction.title)
        defaultAction.target = self
        defaultAction.action = #selector(saveClick)

        colorFormat.addItems(withTitles: ["HEX", "RGB"])
        colorFormat.selectItem(withTitle: settings.colorFormat)
        colorFormat.target = self
        colorFormat.action = #selector(saveClick)

        var y = placeRow(in: card, title: "保存目录", control: directory, y: 48, width: 436)
        y = placeRow(in: card, title: "默认动作", control: defaultAction, y: y, width: 436)
        placeRow(in: card, title: "色值格式", control: colorFormat, y: y, width: 436)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func saveClick() {
        if !directory.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            settings.saveDirectory = URL(fileURLWithPath: directory.stringValue, isDirectory: true)
        }
        if let selected = defaultAction.titleOfSelectedItem,
           let action = CaptureAction.allCases.first(where: { $0.title == selected }) {
            settings.recentAction = action
            onActionChanged()
        }
        settings.colorFormat = colorFormat.titleOfSelectedItem ?? "HEX"
        onSave()
        Toast.show("设置已保存")
    }
}

/// 翻译设置：引擎选择 + DeepSeek API Key + 目标语言。
final class TranslationSectionView: NSView {
    private let engineToggle = EngineToggleView(frame: .zero)
    private let apiKey = SecretKeyField(frame: .zero)
    private let keyLabel = NSTextField(labelWithString: "API Key")
    private let targetLanguage = NSPopUpButton()
    private let debugLabel = NSTextField(labelWithString: "调试日志")
    private let debugSwitch = GlassSwitch(frame: .zero)
    private let openLogButton = NSButton(title: "打开日志", target: nil, action: nil)
    private let hint = NSTextField(labelWithString: "")
    private let card = GlassSectionCard(frame: CGRect(x: 28, y: 28, width: 436, height: 288))
    private let settings: AppSettings
    private let onSave: () -> Void

    private static let languages = ["中文（简体）", "中文（繁体）", "English", "日本語", "한국어"]
    private let keyRowY: CGFloat = 134

    override var isFlipped: Bool { true }

    init(settings: AppSettings, onSave: @escaping () -> Void) {
        self.settings = settings
        self.onSave = onSave
        super.init(frame: CGRect(x: 0, y: 0, width: 492, height: 420))
        addSubview(card)
        sectionTitle("区域翻译", in: card)

        engineToggle.select(settings.translationEngine)
        engineToggle.onChange = { [weak self] value in
            guard let self else { return }
            self.settings.translationEngine = value
            self.relayout()
            self.onSave()
            Toast.show("已切换到\(value.toggleTitle)")
        }

        var titles = Self.languages
        if !titles.contains(settings.translationTargetLanguage) {
            titles.insert(settings.translationTargetLanguage, at: 0)
        }
        targetLanguage.addItems(withTitles: titles)
        targetLanguage.selectItem(withTitle: settings.translationTargetLanguage)
        targetLanguage.target = self
        targetLanguage.action = #selector(saveClick)

        apiKey.stringValue = settings.deepSeekAPIKey
        apiKey.placeholderString = "粘贴 API Key（sk-…）"
        apiKey.onCommit = { [weak self] in self?.saveClick() }

        placeRow(in: card, title: "翻译引擎", control: engineToggle, y: 48, width: 436, height: 34)
        placeRow(in: card, title: "目标语言", control: targetLanguage, y: 94, width: 436)

        // API Key 行手动布局，便于按引擎显隐。
        keyLabel.font = .systemFont(ofSize: 12)
        keyLabel.textColor = .secondaryLabelColor
        keyLabel.frame = CGRect(x: 16, y: keyRowY + 6, width: 120, height: 16)
        card.addSubview(keyLabel)
        apiKey.frame = CGRect(x: 152, y: keyRowY, width: 436 - 152 - 16, height: 28)
        card.addSubview(apiKey)

        debugLabel.font = .systemFont(ofSize: 13)
        debugLabel.textColor = .labelColor
        card.addSubview(debugLabel)
        debugSwitch.setOn(settings.translationDebugLogEnabled, animated: false)
        debugSwitch.target = self
        debugSwitch.action = #selector(saveClick)
        card.addSubview(debugSwitch)

        openLogButton.bezelStyle = .rounded
        openLogButton.controlSize = .small
        openLogButton.font = .systemFont(ofSize: 11)
        openLogButton.target = self
        openLogButton.action = #selector(openLog)
        card.addSubview(openLogButton)

        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .tertiaryLabelColor
        hint.lineBreakMode = .byWordWrapping
        hint.maximumNumberOfLines = 2
        card.addSubview(hint)

        relayout()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 按当前引擎显隐 API Key 行，并把调试行/说明文字挪到最后一行下方。
    private func relayout() {
        let engine = settings.translationEngine
        let needsKey = engine.needsAPIKey
        keyLabel.isHidden = !needsKey
        apiKey.isHidden = !needsKey

        let debugY = needsKey ? keyRowY + 28 + 12 : keyRowY
        debugLabel.frame = CGRect(x: 16, y: debugY + 4, width: 96, height: 18)
        debugSwitch.frame = CGRect(x: 116, y: debugY, width: 46, height: 26)
        openLogButton.frame = CGRect(x: 324, y: debugY, width: 96, height: 24)

        hint.frame = CGRect(x: 16, y: debugY + 32, width: 404, height: 32)
        hint.stringValue = "\(engine.subtitle)。选“区域翻译”动作框选外文，译文会以毛玻璃覆盖在原文上。"
    }

    @objc private func saveClick() {
        settings.deepSeekAPIKey = apiKey.stringValue
        settings.translationTargetLanguage = targetLanguage.titleOfSelectedItem ?? "中文（简体）"
        settings.translationDebugLogEnabled = debugSwitch.isOn
        engineToggle.reload()   // 填完 Key 后开关切换成模型名 + logo
        onSave()
        Toast.show("设置已保存")
    }

    /// 在访达中定位翻译日志文件（不存在则先建目录）。
    @objc private func openLog() {
        let url = TranslationDebugLog.fileURL
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !settings.translationDebugLogEnabled {
                Toast.show("调试日志未开启，勾选后翻译一次即可生成")
            }
            NSWorkspace.shared.activateFileViewerSelecting([url.deletingLastPathComponent()])
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

/// 两模式引擎开关：玻璃轨道 + 两段（头像 + 名称），选中段用主题色填充。
final class EngineToggleView: NSView {
    var onChange: ((TranslationEngine) -> Void)?

    private let order: [TranslationEngine] = [.apple, .deepseek]
    private var segments: [NSButton] = []
    private var current: TranslationEngine = .apple
    private var accent: NSColor { AppSettings.shared.accentColor }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
        build()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 3, left: 3, bottom: 3, right: 3)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        for index in order.indices {
            let button = NSButton(title: "", target: self, action: #selector(tap(_:)))
            button.imagePosition = .imageLeading
            button.isBordered = false
            button.bezelStyle = .regularSquare
            button.wantsLayer = true
            button.layer?.cornerRadius = 7
            button.tag = index
            segments.append(button)
            stack.addArrangedSubview(button)
        }
    }

    func select(_ engine: TranslationEngine) {
        current = engine
        refresh()
    }

    /// 外部（如填完 Key）触发重刷，让「自定义大模型」段切换成模型名 + logo。
    func reload() { refresh() }

    @objc private func tap(_ sender: NSButton) {
        let engine = order[sender.tag]
        guard engine != current else { return }
        current = engine
        refresh()
        onChange?(engine)
    }

    private func refresh() {
        for (index, button) in segments.enumerated() {
            let engine = order[index]
            let on = engine == current
            button.layer?.backgroundColor = on ? accent.withAlphaComponent(0.9).cgColor : NSColor.clear.cgColor
            button.contentTintColor = on ? .white : .secondaryLabelColor
            let (title, image) = display(for: engine)
            button.image = image
            button.attributedTitle = NSAttributedString(string: " " + title, attributes: [
                .foregroundColor: on ? NSColor.white : NSColor.secondaryLabelColor,
                .font: NSFont.systemFont(ofSize: 12, weight: on ? .semibold : .medium)
            ])
        }
    }

    /// 「自定义大模型」在填了 Key 后显示具体模型名 + 品牌 logo。
    private func display(for engine: TranslationEngine) -> (String, NSImage?) {
        switch engine {
        case .apple:
            return ("Apple 原生", symbolImage("apple.logo"))
        case .deepseek:
            if !AppSettings.shared.deepSeekAPIKey.isEmpty {
                let logo = TranslationAsset.image("deepseek1")
                logo?.isTemplate = false   // 保留蓝鲸原色
                logo?.size = NSSize(width: 18, height: 16)
                return ("DeepSeek", logo)
            }
            return ("自定义大模型", symbolImage("sparkles"))
        }
    }

    private func symbolImage(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold))
    }
}

/// 带小眼睛显隐的 API Key 输入框：默认遮住，点眼睛切换明文。
/// 自定义 API Key 输入框：玻璃容器自绘描边 + 聚焦动画；内嵌单行（不换行、横向滚动）输入，
/// 文字有内边距，小眼睛在框内右侧控制明文/密文。
final class SecretKeyField: NSView {
    var onCommit: (() -> Void)?
    var placeholderString: String? {
        didSet {
            plain.placeholderString = placeholderString
            secure.placeholderString = placeholderString
        }
    }
    var stringValue: String {
        get { revealed ? plain.stringValue : secure.stringValue }
        set { plain.stringValue = newValue; secure.stringValue = newValue }
    }

    private let plain = BareTextField()
    private let secure = BareSecureField()
    private let eye = NSButton()
    private var revealed = false
    private var focused = false
    private var accent: NSColor { AppSettings.shared.accentColor }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        build()
        updateChrome(animated: false)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        for field in [plain, secure] as [NSTextField] {
            field.target = self
            field.action = #selector(committed)
            field.translatesAutoresizingMaskIntoConstraints = false
            addSubview(field)
            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),   // 左内边距
                field.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -32), // 给小眼睛留位
                field.centerYAnchor.constraint(equalTo: centerYAnchor),
                field.heightAnchor.constraint(equalToConstant: 18)
            ])
        }
        plain.onFocusChange = { [weak self] on in self?.setFocused(on) }
        secure.onFocusChange = { [weak self] on in self?.setFocused(on) }
        plain.isHidden = true

        eye.target = self
        eye.action = #selector(toggleReveal)
        eye.isBordered = false
        eye.bezelStyle = .regularSquare
        eye.image = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: "显示")
        eye.contentTintColor = .secondaryLabelColor
        eye.translatesAutoresizingMaskIntoConstraints = false
        addSubview(eye)
        NSLayoutConstraint.activate([
            eye.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            eye.centerYAnchor.constraint(equalTo: centerYAnchor),
            eye.widthAnchor.constraint(equalToConstant: 22),
            eye.heightAnchor.constraint(equalToConstant: 20)
        ])
    }

    private func setFocused(_ on: Bool) {
        guard focused != on else { return }
        focused = on
        updateChrome(animated: true)
    }

    /// 聚焦时描边转主题色、底色略提亮，带过渡动画。
    private func updateChrome(animated: Bool) {
        let border = (focused ? accent.withAlphaComponent(0.9) : NSColor.white.withAlphaComponent(0.24)).cgColor
        let bg = (focused ? NSColor.white.withAlphaComponent(0.12) : NSColor.white.withAlphaComponent(0.07)).cgColor
        if animated {
            let anim = CABasicAnimation(keyPath: "borderColor")
            anim.fromValue = layer?.borderColor
            anim.toValue = border
            anim.duration = 0.18
            layer?.add(anim, forKey: "borderColor")
        }
        layer?.borderColor = border
        layer?.backgroundColor = bg
        layer?.borderWidth = focused ? 1.5 : 1
    }

    @objc private func committed() { onCommit?() }

    @objc private func toggleReveal() {
        let value = stringValue
        revealed.toggle()
        plain.stringValue = value
        secure.stringValue = value
        plain.isHidden = !revealed
        secure.isHidden = revealed
        eye.image = NSImage(systemSymbolName: revealed ? "eye" : "eye.slash", accessibilityDescription: nil)
        eye.contentTintColor = revealed ? accent : .secondaryLabelColor
        window?.makeFirstResponder(revealed ? plain : secure)
    }
}

/// 单行、无边框、透明底的输入框，聚焦时回调（供 SecretKeyField 画容器）。
final class BareTextField: NSTextField {
    var onFocusChange: ((Bool) -> Void)?

    override init(frame frameRect: NSRect) { super.init(frame: frameRect); setupBare() }
    required init?(coder: NSCoder) { super.init(coder: coder); setupBare() }

    private func setupBare() {
        isBordered = false
        drawsBackground = false
        focusRingType = .none
        font = .systemFont(ofSize: 12, weight: .medium)
        textColor = .labelColor
        usesSingleLineMode = true
        lineBreakMode = .byClipping
        cell?.wraps = false
        cell?.isScrollable = true
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { onFocusChange?(true) }
        return ok
    }

    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        onFocusChange?(false)
    }
}

/// 单行密文版本，与 BareTextField 同款配置。
final class BareSecureField: NSSecureTextField {
    var onFocusChange: ((Bool) -> Void)?

    override init(frame frameRect: NSRect) { super.init(frame: frameRect); setupBare() }
    required init?(coder: NSCoder) { super.init(coder: coder); setupBare() }

    private func setupBare() {
        isBordered = false
        drawsBackground = false
        focusRingType = .none
        font = .systemFont(ofSize: 12, weight: .medium)
        textColor = .labelColor
        usesSingleLineMode = true
        lineBreakMode = .byClipping
        cell?.wraps = false
        cell?.isScrollable = true
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { onFocusChange?(true) }
        return ok
    }

    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        onFocusChange?(false)
    }
}

// MARK: - Shared glass components

/// 分区玻璃卡片：白色低透明度填充 + 描边，衬在每个分区的标题与控件之下。
final class GlassSectionCard: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 16, yRadius: 16)
        NSColor.white.withAlphaComponent(0.05).setFill()
        path.fill()
        NSColor.white.withAlphaComponent(0.20).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

/// 文本输入框：去掉系统白底 bezel，换成和分区卡片同一套玻璃描边。
final class GlassTextField: NSTextField {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        isBordered = false
        drawsBackground = false
        focusRingType = .none
        font = .systemFont(ofSize: 12, weight: .medium)
        textColor = .labelColor
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.07).cgColor
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.24).cgColor
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            layer?.borderColor = NSColor.white.withAlphaComponent(0.42).cgColor
        }
        return result
    }

    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        layer?.borderColor = NSColor.white.withAlphaComponent(0.24).cgColor
    }
}

/// 强调色描边按钮：用于需要用户主动触发的动作（如授权），区别于普通玻璃卡片。
final class AccentGhostButton: NSButton {
    private var accent: NSColor { AppSettings.shared.accentColor }

    init(title: String) {
        super.init(frame: .zero)
        self.title = title
        isBordered = false
        wantsLayer = true
        font = .systemFont(ofSize: 12, weight: .semibold)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        accent.withAlphaComponent(isHighlighted ? 0.16 : 0.08).setFill()
        path.fill()
        accent.withAlphaComponent(0.42).setStroke()
        path.lineWidth = 1
        path.stroke()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: accent
        ]
        let text = NSString(string: title)
        let size = text.size(withAttributes: attrs)
        text.draw(at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attrs)
    }
}

private extension NSImage {
    func tinted(with color: NSColor) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        color.set()
        let rect = NSRect(origin: .zero, size: size)
        rect.fill(using: .sourceOver)
        draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1)
        image.unlockFocus()
        return image
    }
}
