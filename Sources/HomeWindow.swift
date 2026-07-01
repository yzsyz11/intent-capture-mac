import AppKit
import ApplicationServices

enum HomeSection: CaseIterable {
    case action, hotkeys, clipboard, mouse, saving

    var title: String {
        switch self {
        case .action: return "默认动作"
        case .hotkeys: return "快捷键"
        case .clipboard: return "剪贴板拓展坞"
        case .mouse: return "鼠标中键"
        case .saving: return "默认与保存"
        }
    }

    var symbolName: String {
        switch self {
        case .action: return "target"
        case .hotkeys: return "keyboard"
        case .clipboard: return "clipboard"
        case .mouse: return "computermouse"
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
    private let saveSection: SaveSectionView
    private var sections: [HomeSection: NSView] = [:]

    override var isFlipped: Bool { true }

    init(settings: AppSettings, onSelectAction: @escaping (CaptureAction) -> Void, onSettingsSaved: @escaping () -> Void) {
        self.onSelectAction = onSelectAction
        actionSection = ActionSectionView(settings: settings)
        hotkeySection = HotkeySectionView(settings: settings, onSave: onSettingsSaved)
        clipboardSection = ClipboardSectionView(settings: settings, onSave: onSettingsSaved)
        mouseSection = MouseSectionView(settings: settings, onSave: onSettingsSaved)
        saveSection = SaveSectionView(settings: settings, onSave: onSettingsSaved, onActionChanged: {})
        super.init(frame: CGRect(x: 0, y: 0, width: 680, height: 420))
        wantsLayer = true
        saveSection.onActionChanged = { [weak self] in self?.actionSection.reloadCurrent() }
        build()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func build() {
        backgroundEffect.material = .underWindowBackground
        backgroundEffect.blendingMode = .behindWindow
        backgroundEffect.state = .active
        backgroundEffect.alphaValue = 0.5
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
        NSColor.white.withAlphaComponent(0.03).setFill()
        bounds.fill()
        let line = NSBezierPath()
        line.move(to: CGPoint(x: bounds.width - 0.5, y: 0))
        line.line(to: CGPoint(x: bounds.width - 0.5, y: bounds.height))
        line.lineWidth = 1
        NSColor.white.withAlphaComponent(0.14).setStroke()
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
    private static let accent = NSColor(calibratedRed: 0.18, green: 0.65, blue: 0.78, alpha: 1)

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
            Self.accent.withAlphaComponent(0.18).setFill()
        } else if isHovering {
            NSColor.white.withAlphaComponent(0.08).setFill()
        } else {
            NSColor.clear.setFill()
        }
        path.fill()
        if isActive {
            path.lineWidth = 1
            Self.accent.withAlphaComponent(0.40).setStroke()
            path.stroke()
        }

        if let symbol = NSImage(systemSymbolName: section.symbolName, accessibilityDescription: nil) {
            let tinted = symbol.tinted(with: isActive ? Self.accent : NSColor.secondaryLabelColor)
            tinted.draw(in: CGRect(x: 10, y: bounds.midY - 8, width: 16, height: 16))
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12.5, weight: isActive ? .semibold : .regular),
            .foregroundColor: isActive ? Self.accent : NSColor.labelColor
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
        let accent = NSColor(calibratedRed: 0.18, green: 0.65, blue: 0.78, alpha: 1)
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
                .foregroundColor: NSColor(calibratedRed: 0.18, green: 0.65, blue: 0.78, alpha: 1)
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
    private let card = GlassSectionCard(frame: CGRect(x: 28, y: 28, width: 436, height: 172))

    override var isFlipped: Bool { true }

    init(settings: AppSettings, onSave: @escaping () -> Void) {
        actionHotkey = HotkeyRecorderButton(hotkey: settings.actionHotkey)
        panelHotkey = HotkeyRecorderButton(hotkey: settings.panelHotkey)
        clipboardDockHotkey = HotkeyRecorderButton(hotkey: settings.clipboardDockHotkey)
        super.init(frame: CGRect(x: 0, y: 0, width: 492, height: 420))
        addSubview(card)
        sectionTitle("键盘快捷键", in: card)

        var y = placeRow(in: card, title: "执行默认动作", control: actionHotkey, y: 48, width: 436)
        y = placeRow(in: card, title: "打开主页", control: panelHotkey, y: y, width: 436)
        placeRow(in: card, title: "剪贴板拓展坞", control: clipboardDockHotkey, y: y, width: 436)

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

final class ClipboardSectionView: NSView {
    private let toggle = NSButton(checkboxWithTitle: "启用剪贴板历史", target: nil, action: nil)
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

        toggle.state = settings.clipboardHistoryEnabled ? .on : .off
        toggle.target = self
        toggle.action = #selector(toggleChanged)
        toggle.frame = CGRect(x: 16, y: 48, width: 300, height: 20)
        card.addSubview(toggle)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func toggleChanged() {
        settings.clipboardHistoryEnabled = toggle.state == .on
        onSave()
        Toast.show(settings.clipboardHistoryEnabled ? "已启用剪贴板历史" : "已关闭剪贴板历史")
    }
}

final class MouseSectionView: NSView {
    private let toggle = NSButton(checkboxWithTitle: "启用鼠标中键触发", target: nil, action: nil)
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

        toggle.state = settings.middleClickEnabled ? .on : .off
        toggle.target = self
        toggle.action = #selector(toggleChanged)
        toggle.frame = CGRect(x: 16, y: 48, width: 300, height: 20)
        card.addSubview(toggle)

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
        settings.middleClickEnabled = toggle.state == .on
        onSave()
        Toast.show(settings.middleClickEnabled ? "已启用鼠标中键触发" : "已关闭鼠标中键触发")
    }

    @objc private func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        refreshPermissionStatus()
        Toast.show("授权后请退出并重新打开 Intent Capture。")
    }

    func refreshPermissionStatus() {
        if AXIsProcessTrusted() {
            statusLabel.stringValue = "辅助功能权限已生效；保存后会重启中键监听"
        } else {
            statusLabel.stringValue = "辅助功能权限未对当前 App 生效；可能是旧条目或需重启"
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
    private static let accent = NSColor(calibratedRed: 0.18, green: 0.65, blue: 0.78, alpha: 1)

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
        Self.accent.withAlphaComponent(isHighlighted ? 0.16 : 0.08).setFill()
        path.fill()
        Self.accent.withAlphaComponent(0.42).setStroke()
        path.lineWidth = 1
        path.stroke()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: Self.accent
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
