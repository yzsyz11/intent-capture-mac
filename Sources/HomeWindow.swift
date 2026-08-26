import AppKit
import ApplicationServices

// MARK: - 分区

enum HomeSection: CaseIterable {
    case action, saving, trigger, features, appearance

    var title: String {
        switch self {
        case .action: return "默认动作"
        case .saving: return "保存位置"
        case .trigger: return "触发"
        case .features: return "功能"
        case .appearance: return "外观"
        }
    }

    var symbolName: String {
        switch self {
        case .action: return "target"
        case .saving: return "folder"
        case .trigger: return "bolt"
        case .features: return "sparkles"
        case .appearance: return "paintpalette"
        }
    }
}

// MARK: - 窗口

/// 主页 + 设置合并成的单窗口：左侧浅色侧边栏导航，右侧内容区随选中分区弹簧切换。
final class HomeWindow: NSWindow {
    private let homeView: HomeWindowView

    init(onSelectAction: @escaping (CaptureAction) -> Void, onSettingsSaved: @escaping () -> Void) {
        homeView = HomeWindowView(
            settings: AppSettings.shared,
            onSelectAction: onSelectAction,
            onSettingsSaved: onSettingsSaved
        )
        super.init(
            contentRect: CGRect(x: 0, y: 0, width: Design.Layout.windowWidth, height: Design.Layout.windowHeight),
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
        homeView.select(section, animated: false)
        if !isVisible { center() }
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func refreshPermissionStatus() {
        homeView.refreshPermissionStatus()
    }
}

// MARK: - 根视图

final class HomeWindowView: NSView {
    private let onSelectAction: (CaptureAction) -> Void
    private let sidebar = SidebarView()
    private let contentContainer = NSView()

    private let dashboard: DashboardSectionView
    private let savingSection: SavingSectionView
    private let triggerSection: TriggerSectionView
    private let featuresSection: FeaturesSectionView
    private let appearanceSection: AppearanceSectionView
    private var sections: [HomeSection: NSView] = [:]
    private var current: HomeSection = .action

    override var isFlipped: Bool { true }

    init(settings: AppSettings, onSelectAction: @escaping (CaptureAction) -> Void, onSettingsSaved: @escaping () -> Void) {
        self.onSelectAction = onSelectAction
        dashboard = DashboardSectionView(settings: settings)
        savingSection = SavingSectionView(settings: settings, onSave: onSettingsSaved)
        triggerSection = TriggerSectionView(settings: settings, onSave: onSettingsSaved)
        featuresSection = FeaturesSectionView(settings: settings, onSave: onSettingsSaved)
        appearanceSection = AppearanceSectionView(settings: settings)
        super.init(frame: CGRect(x: 0, y: 0, width: Design.Layout.windowWidth, height: Design.Layout.windowHeight))
        wantsLayer = true
        appearanceSection.onAccentChanged = { [weak self] in self?.refreshAccent() }
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build() {
        layer?.backgroundColor = Design.Color.windowBackground.cgColor

        sidebar.frame = CGRect(x: 0, y: 0, width: Design.Layout.sidebarWidth, height: bounds.height)
        sidebar.autoresizingMask = [.height]
        sidebar.onSelect = { [weak self] section in self?.select(section, animated: true) }
        addSubview(sidebar)

        contentContainer.frame = CGRect(x: Design.Layout.sidebarWidth, y: 0,
                                        width: bounds.width - Design.Layout.sidebarWidth, height: bounds.height)
        contentContainer.autoresizingMask = [.width, .height]
        addSubview(contentContainer)

        // 点仪表盘宫格：执行动作并关窗（保留原 launcher 语义）。
        dashboard.onSelect = { [weak self] action in self?.onSelectAction(action) }
        // 点底部状态条：跳到对应设置页。
        dashboard.onJump = { [weak self] section in self?.select(section, animated: true) }

        sections = [
            .action: dashboard,
            .saving: savingSection,
            .trigger: triggerSection,
            .features: featuresSection,
            .appearance: appearanceSection
        ]
        for (_, view) in sections {
            view.wantsLayer = true
            view.frame = contentContainer.bounds
            view.autoresizingMask = [.width, .height]
            view.isHidden = true
            contentContainer.addSubview(view)
        }
        select(.action, animated: false)
    }

    /// 切换分区。弹簧交叉溶解（尊重减弱动态）。
    func select(_ section: HomeSection, animated: Bool) {
        sidebar.setActive(section, animated: animated)
        let old = sections[current]
        guard let new = sections[section] else { return }
        if section == .action { dashboard.reload() }
        if section == .trigger { triggerSection.refreshPermissionStatus() }

        if !animated || Design.Motion.reduceMotion || old == nil || old === new {
            for (key, view) in sections { view.isHidden = key != section; view.alphaValue = 1 }
            current = section
            return
        }

        // 立即隐藏旧页（杜绝两页短暂重合），新页从 alpha 0 + 6px 上浮淡入落定。
        old?.isHidden = true
        old?.alphaValue = 1
        new.isHidden = false
        new.alphaValue = 1
        if let l = new.layer {
            l.removeAnimation(forKey: "pageIn")
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0; fade.toValue = 1
            let move = CABasicAnimation(keyPath: "transform.translation.y")
            move.fromValue = 6; move.toValue = 0
            let group = CAAnimationGroup()
            group.animations = [fade, move]
            group.duration = Design.Motion.pageResponse
            group.timingFunction = CAMediaTimingFunction(name: .easeOut)
            l.add(group, forKey: "pageIn")
        }
        current = section
    }

    func refreshPermissionStatus() { triggerSection.refreshPermissionStatus() }

    private func refreshAccent() {
        sidebar.reapplyAccent()
        func redraw(_ view: NSView) { view.needsDisplay = true; view.subviews.forEach(redraw) }
        sections.values.forEach(redraw)
    }
}

// MARK: - 侧边栏

final class SidebarView: NSView {
    var onSelect: ((HomeSection) -> Void)?
    private var buttons: [HomeSection: NavItemButton] = [:]
    private let pill = CALayer()
    private var active: HomeSection = .action

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: CGRect(x: 0, y: 0, width: Design.Layout.sidebarWidth, height: Design.Layout.windowHeight))
        wantsLayer = true
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        Design.Color.sidebarFill.setFill()
        bounds.fill()
        let line = NSBezierPath()
        line.move(to: CGPoint(x: bounds.width - 0.5, y: 0))
        line.line(to: CGPoint(x: bounds.width - 0.5, y: bounds.height))
        line.lineWidth = 1
        Design.Color.separator.setStroke()
        line.stroke()
    }

    private func build() {
        // 交通灯占顶部 ~30pt，导航项从下方开始。
        pill.cornerRadius = Design.Radius.nav
        pill.backgroundColor = Design.Color.accentTint(0.15).cgColor
        layer?.addSublayer(pill)

        var y: CGFloat = 44
        for section in HomeSection.allCases {
            let button = NavItemButton(section: section)
            button.target = self
            button.action = #selector(tap(_:))
            button.frame = CGRect(x: 12, y: y, width: Design.Layout.sidebarWidth - 24, height: Design.Layout.navItemHeight)
            addSubview(button)
            buttons[section] = button
            y += Design.Layout.navItemHeight + Design.Layout.navItemGap
        }
        pill.frame = buttons[active]?.frame ?? .zero
        setActive(.action, animated: false)
    }

    @objc private func tap(_ sender: NavItemButton) { onSelect?(sender.section) }

    func setActive(_ section: HomeSection, animated: Bool) {
        active = section
        buttons.forEach { $0.value.isActive = $0.key == section }
        guard let target = buttons[section]?.frame else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(!animated || Design.Motion.reduceMotion)
        if animated && !Design.Motion.reduceMotion { CATransaction.setAnimationDuration(Design.Motion.pageResponse) }
        pill.frame = target
        CATransaction.commit()
    }

    func reapplyAccent() {
        pill.backgroundColor = Design.Color.accentTint(0.15).cgColor
        buttons.values.forEach { $0.needsDisplay = true }
    }
}

final class NavItemButton: NSButton {
    let section: HomeSection
    var isActive: Bool = false { didSet { needsDisplay = true } }
    private var isHovering = false
    private var accent: NSColor { Design.Color.accent }

    init(section: HomeSection) {
        self.section = section
        super.init(frame: .zero)
        title = ""
        isBordered = false
        wantsLayer = true
        toolTip = section.title
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { isHovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { isHovering = false; needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        // 选中态背景由侧栏的滑块 pill 提供，这里只画 hover 底 + 图标 + 文字。
        if isHovering && !isActive {
            let path = NSBezierPath(roundedRect: bounds, xRadius: Design.Radius.nav, yRadius: Design.Radius.nav)
            NSColor.black.withAlphaComponent(0.05).setFill()
            path.fill()
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

// MARK: - 分区脚手架

/// 在 section 顶部建一列竖直堆叠（含内边距），往里加分组标题 + 卡片；卡片自动撑满列宽。
private func makeFormColumn(in host: NSView) -> NSStackView {
    let col = NSStackView()
    col.orientation = .vertical
    col.alignment = .leading
    col.spacing = 16
    col.translatesAutoresizingMaskIntoConstraints = false
    host.addSubview(col)
    let inset = Design.Layout.contentInset
    // 顶约束由调用方锚到标题底部（各页都有分区大标题），这里只固定左右。
    NSLayoutConstraint.activate([
        col.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: inset),
        col.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -inset)
    ])
    return col
}

/// 把「分组标题 + 卡片」加进列：标题贴左，卡片撑满列宽，间距收紧到 8。
private func addGroup(_ column: NSStackView, header: String, card: SettingsCard) {
    let head = GroupHeader(header)
    column.addArrangedSubview(head)
    column.setCustomSpacing(8, after: head)
    column.addArrangedSubview(card)
    card.leadingAnchor.constraint(equalTo: column.leadingAnchor).isActive = true
    card.trailingAnchor.constraint(equalTo: column.trailingAnchor).isActive = true
}

// MARK: - 默认动作（仪表盘）

final class DashboardSectionView: NSView {
    var onSelect: ((CaptureAction) -> Void)?
    var onJump: ((HomeSection) -> Void)?

    private let settings: AppSettings
    private let currentIcon = NSImageView()
    private let currentName = NSTextField(labelWithString: "")
    private let currentDetail = NSTextField(labelWithString: "")
    private var tiles: [ActionTile] = []
    private let statusBar: DashboardStatusBar

    override var isFlipped: Bool { true }

    init(settings: AppSettings) {
        self.settings = settings
        statusBar = DashboardStatusBar(settings: settings)
        super.init(frame: .zero)
        build()
        reload()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build() {
        let inset = Design.Layout.contentInset

        let title = NSTextField(labelWithString: "默认动作")
        title.font = Design.Font.pageTitle
        title.textColor = Design.Color.textPrimary
        title.translatesAutoresizingMaskIntoConstraints = false
        addSubview(title)

        // 「当前」信息条
        let curBar = NSView()
        curBar.wantsLayer = true
        curBar.layer?.backgroundColor = Design.Color.statusBarFill.cgColor
        curBar.layer?.cornerRadius = 10
        curBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(curBar)

        let curLabel = NSTextField(labelWithString: "当前")
        curLabel.font = Design.Font.secondary
        curLabel.textColor = Design.Color.textTertiary
        currentIcon.contentTintColor = Design.Color.accent
        currentName.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        currentName.textColor = Design.Color.textPrimary
        currentDetail.font = Design.Font.secondary
        currentDetail.textColor = Design.Color.textTertiary
        let curStack = NSStackView(views: [curLabel, currentIcon, currentName, currentDetail])
        curStack.orientation = .horizontal
        curStack.alignment = .centerY
        curStack.spacing = 8
        curStack.translatesAutoresizingMaskIntoConstraints = false
        curBar.addSubview(curStack)
        NSLayoutConstraint.activate([
            curStack.leadingAnchor.constraint(equalTo: curBar.leadingAnchor, constant: 12),
            curStack.trailingAnchor.constraint(lessThanOrEqualTo: curBar.trailingAnchor, constant: -12),
            curStack.centerYAnchor.constraint(equalTo: curBar.centerYAnchor),
            currentIcon.widthAnchor.constraint(equalToConstant: 16),
            currentIcon.heightAnchor.constraint(equalToConstant: 16)
        ])

        // 3×2 宫格
        let grid = NSStackView()
        grid.orientation = .vertical
        grid.distribution = .fillEqually
        grid.spacing = 8
        grid.translatesAutoresizingMaskIntoConstraints = false
        addSubview(grid)
        var rowStack: NSStackView?
        for (i, action) in CaptureAction.allCases.enumerated() {
            if i % 3 == 0 {
                let r = NSStackView()
                r.orientation = .horizontal
                r.distribution = .fillEqually
                r.spacing = 8
                grid.addArrangedSubview(r)
                r.leadingAnchor.constraint(equalTo: grid.leadingAnchor).isActive = true
                r.trailingAnchor.constraint(equalTo: grid.trailingAnchor).isActive = true
                rowStack = r
            }
            let tile = ActionTile(action: action)
            tile.target = self
            tile.action = #selector(tap(_:))
            tiles.append(tile)
            rowStack?.addArrangedSubview(tile)
        }

        statusBar.translatesAutoresizingMaskIntoConstraints = false
        statusBar.onJump = { [weak self] section in self?.onJump?(section) }
        addSubview(statusBar)

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: topAnchor, constant: inset),
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),

            curBar.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 14),
            curBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            curBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            curBar.heightAnchor.constraint(equalToConstant: 44),

            grid.topAnchor.constraint(equalTo: curBar.bottomAnchor, constant: 14),
            grid.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            grid.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            grid.heightAnchor.constraint(equalToConstant: 66 * 2 + 8), // 两排贴紧（行距 8）

            statusBar.topAnchor.constraint(greaterThanOrEqualTo: grid.bottomAnchor, constant: 14),
            statusBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            statusBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            statusBar.heightAnchor.constraint(equalToConstant: Design.Layout.statusBarHeight),
            statusBar.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -inset)
        ])
    }

    /// 刷新「当前」条、宫格选中态、状态条数值。
    func reload() {
        let action = settings.recentAction
        currentIcon.image = NSImage(systemSymbolName: action.symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold))
        currentName.stringValue = action.title
        currentDetail.stringValue = "· " + action.detail
        tiles.forEach { $0.setSelected($0.captureAction == action) }
        statusBar.reload()
    }

    @objc private func tap(_ sender: ActionTile) { onSelect?(sender.captureAction) }
}

/// 仪表盘动作宫格单元：图标块在上、名称居中，选中=青环+青图标+右上对勾。
final class ActionTile: NSControl {
    let captureAction: CaptureAction
    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let check = NSImageView()
    private var selectedState = false
    private var hovering = false

    init(action: CaptureAction) {
        self.captureAction = action
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = Design.Radius.action
        layer?.borderWidth = 1
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 66).isActive = true

        iconView.image = NSImage(systemSymbolName: action.symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 18, weight: .regular))
        iconView.translatesAutoresizingMaskIntoConstraints = false
        label.stringValue = action.title
        label.font = Design.Font.rowLabel
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        let v = NSStackView(views: [iconView, label])
        v.orientation = .vertical
        v.alignment = .centerX
        v.spacing = 6
        v.translatesAutoresizingMaskIntoConstraints = false
        addSubview(v)

        check.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .bold))
        check.contentTintColor = Design.Color.accent
        check.isHidden = true
        check.translatesAutoresizingMaskIntoConstraints = false
        addSubview(check)

        NSLayoutConstraint.activate([
            v.centerXAnchor.constraint(equalTo: centerXAnchor),
            v.centerYAnchor.constraint(equalTo: centerYAnchor),
            check.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            check.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            check.widthAnchor.constraint(equalToConstant: 14),
            check.heightAnchor.constraint(equalToConstant: 14)
        ])
        updateStyle()
    }

    required init?(coder: NSCoder) { fatalError() }

    func setSelected(_ on: Bool) { selectedState = on; updateStyle() }
    // 子视图（图标/文字）不吞点击：整块 tile 作为原子点击区。
    override func hitTest(_ point: NSPoint) -> NSView? { super.hitTest(point) != nil ? self : nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true; updateStyle() }
    override func mouseExited(with event: NSEvent) { hovering = false; updateStyle() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    override func mouseDown(with event: NSEvent) {
        animator().alphaValue = 0.9
        sendAction(action, to: target)
    }
    override func mouseUp(with event: NSEvent) { animator().alphaValue = 1 }

    private func updateStyle() {
        let accent = Design.Color.accent
        if selectedState {
            layer?.backgroundColor = accent.withAlphaComponent(0.08).cgColor
            layer?.borderColor = accent.cgColor
            iconView.contentTintColor = accent
            label.textColor = accent
            label.font = NSFont.systemFont(ofSize: 12.5, weight: .medium)
            check.isHidden = false
        } else {
            layer?.backgroundColor = (hovering ? NSColor.black.withAlphaComponent(0.03) : Design.Color.cardFill).cgColor
            layer?.borderColor = Design.Color.cardBorder.cgColor
            iconView.contentTintColor = Design.Color.textSecondary
            label.textColor = Design.Color.textPrimary
            label.font = Design.Font.rowLabel
            check.isHidden = true
        }
    }
}

/// 仪表盘底部下沉状态条：快捷键 / 中键 / 剪贴板，点一下跳对应页。
final class DashboardStatusBar: NSView {
    var onJump: ((HomeSection) -> Void)?
    private let settings: AppSettings
    private var items: [StatusItem] = []

    override var isFlipped: Bool { true }

    init(settings: AppSettings) {
        self.settings = settings
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = Design.Color.statusBarFill.cgColor
        layer?.cornerRadius = 10
        build()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        let specs: [(String, String, HomeSection)] = [
            ("keyboard", "快捷键", .trigger),
            ("computermouse", "中键", .trigger),
            ("clipboard", "剪贴板", .features)
        ]
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        for (i, spec) in specs.enumerated() {
            let item = StatusItem(symbol: spec.0, label: spec.1, section: spec.2)
            item.target = self
            item.action = #selector(tap(_:))
            items.append(item)
            stack.addArrangedSubview(item)
            if i < specs.count - 1 {
                let sep = NSView()
                sep.wantsLayer = true
                sep.layer?.backgroundColor = Design.Color.separator.cgColor
                sep.translatesAutoresizingMaskIntoConstraints = false
                addSubview(sep)
                NSLayoutConstraint.activate([
                    sep.widthAnchor.constraint(equalToConstant: 0.5),
                    sep.topAnchor.constraint(equalTo: topAnchor, constant: 12),
                    sep.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
                    sep.leadingAnchor.constraint(equalTo: item.trailingAnchor)
                ])
            }
        }
    }

    func reload() {
        items[0].setValue(settings.actionHotkey.displayText)
        items[1].setValue(settings.middleClickEnabled ? "已启用" : "已关闭", highlighted: settings.middleClickEnabled)
        items[2].setValue(settings.clipboardHistoryEnabled ? "已启用" : "已关闭", highlighted: settings.clipboardHistoryEnabled)
    }

    @objc private func tap(_ sender: StatusItem) { onJump?(sender.section) }
}

final class StatusItem: NSControl {
    let section: HomeSection
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let value = NSTextField(labelWithString: "")
    private var hovering = false

    init(symbol: String, label labelText: String, section: HomeSection) {
        self.section = section
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .regular))
        icon.contentTintColor = Design.Color.textTertiary
        icon.translatesAutoresizingMaskIntoConstraints = false
        label.stringValue = labelText
        label.font = Design.Font.secondary
        label.textColor = Design.Color.textTertiary
        value.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        value.textColor = Design.Color.textPrimary

        let top = NSStackView(views: [icon, label])
        top.orientation = .horizontal
        top.spacing = 4
        top.alignment = .centerY
        let v = NSStackView(views: [top, value])
        v.orientation = .vertical
        v.alignment = .centerX
        v.spacing = 2
        v.translatesAutoresizingMaskIntoConstraints = false
        addSubview(v)
        NSLayoutConstraint.activate([
            v.centerXAnchor.constraint(equalTo: centerXAnchor),
            v.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 13),
            icon.heightAnchor.constraint(equalToConstant: 13)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func setValue(_ text: String, highlighted: Bool = false) {
        value.stringValue = text
        value.textColor = highlighted ? Design.Color.accent : Design.Color.textPrimary
    }
    override func hitTest(_ point: NSPoint) -> NSView? { super.hitTest(point) != nil ? self : nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { layer?.backgroundColor = NSColor.black.withAlphaComponent(0.04).cgColor }
    override func mouseExited(with event: NSEvent) { layer?.backgroundColor = NSColor.clear.cgColor }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
    override func mouseDown(with event: NSEvent) { sendAction(action, to: target) }
}

// MARK: - 保存位置

final class SavingSectionView: NSView {
    private let directory = GlassTextField()
    private let colorFormat = NSSegmentedControl(labels: ["HEX", "RGB"], trackingMode: .selectOne, target: nil, action: nil)
    private let settings: AppSettings
    private let onSave: () -> Void

    override var isFlipped: Bool { true }

    init(settings: AppSettings, onSave: @escaping () -> Void) {
        self.settings = settings
        self.onSave = onSave
        super.init(frame: .zero)

        let title = pageTitleLabel("保存位置")
        addSubview(title)
        let col = makeFormColumn(in: self)
        col.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 14).isActive = true

        directory.stringValue = settings.saveDirectory.path
        directory.target = self
        directory.action = #selector(save)
        directory.translatesAutoresizingMaskIntoConstraints = false
        directory.heightAnchor.constraint(equalToConstant: 26).isActive = true
        directory.widthAnchor.constraint(equalToConstant: 190).isActive = true
        let choose = NSButton(title: "选择…", target: self, action: #selector(pickDirectory))
        choose.bezelStyle = .rounded
        choose.controlSize = .small
        let dirTrailing = NSStackView(views: [directory, choose])
        dirTrailing.spacing = 8

        let imgCard = SettingsCard()
        imgCard.addRow(SettingRow.make(title: "保存目录", control: dirTrailing))
        addGroup(col, header: "图片", card: imgCard)

        colorFormat.selectedSegment = settings.colorFormat == "RGB" ? 1 : 0
        colorFormat.target = self
        colorFormat.action = #selector(save)
        let colorCard = SettingsCard()
        colorCard.addRow(SettingRow.make(title: "复制格式", control: colorFormat))
        addGroup(col, header: "色值", card: colorCard)

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: topAnchor, constant: Design.Layout.contentInset),
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Design.Layout.contentInset)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func pickDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = settings.saveDirectory
        if panel.runModal() == .OK, let url = panel.url {
            directory.stringValue = url.path
            save()
        }
    }

    @objc private func save() {
        let path = directory.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !path.isEmpty { settings.saveDirectory = URL(fileURLWithPath: path, isDirectory: true) }
        settings.colorFormat = colorFormat.selectedSegment == 1 ? "RGB" : "HEX"
        onSave()
        Toast.show("设置已保存")
    }
}

// MARK: - 触发（快捷键 + 鼠标中键）

final class TriggerSectionView: NSView {
    private let actionHotkey: HotkeyRecorderButton
    private let panelHotkey: HotkeyRecorderButton
    private let clipboardDockHotkey: HotkeyRecorderButton
    private let mouseSwitch = GlassSwitch(frame: .zero)
    private let permStatus = NSTextField(labelWithString: "")
    private let permButton = AccentGhostButton(title: "去授权")
    private let settings: AppSettings
    private let onSave: () -> Void

    override var isFlipped: Bool { true }

    init(settings: AppSettings, onSave: @escaping () -> Void) {
        self.settings = settings
        self.onSave = onSave
        actionHotkey = HotkeyRecorderButton(hotkey: settings.actionHotkey)
        panelHotkey = HotkeyRecorderButton(hotkey: settings.panelHotkey)
        clipboardDockHotkey = HotkeyRecorderButton(hotkey: settings.clipboardDockHotkey)
        super.init(frame: .zero)

        let title = pageTitleLabel("触发")
        addSubview(title)
        let col = makeFormColumn(in: self)
        col.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 14).isActive = true

        for recorder in [actionHotkey, panelHotkey, clipboardDockHotkey] {
            recorder.translatesAutoresizingMaskIntoConstraints = false
            recorder.widthAnchor.constraint(equalToConstant: 150).isActive = true
            recorder.heightAnchor.constraint(equalToConstant: 28).isActive = true
        }
        let keyCard = SettingsCard()
        keyCard.addRow(SettingRow.make(title: "执行默认动作", control: actionHotkey))
        keyCard.addRow(SettingRow.make(title: "打开主页", control: panelHotkey))
        keyCard.addRow(SettingRow.make(title: "剪贴板拓展坞", control: clipboardDockHotkey))
        addGroup(col, header: "键盘快捷键", card: keyCard)

        mouseSwitch.setOn(settings.middleClickEnabled, animated: false)
        mouseSwitch.target = self
        mouseSwitch.action = #selector(toggleMouse)
        permStatus.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        permButton.target = self
        permButton.action = #selector(requestAccessibility)
        permButton.translatesAutoresizingMaskIntoConstraints = false
        permButton.widthAnchor.constraint(equalToConstant: 84).isActive = true
        permButton.heightAnchor.constraint(equalToConstant: 26).isActive = true
        let permWrap = NSStackView(views: [permStatus, permButton])
        permWrap.orientation = .horizontal
        permWrap.spacing = 8
        permWrap.alignment = .centerY

        let mouseCard = SettingsCard()
        mouseCard.addRow(SettingRow.make(title: "启用中键触发", control: mouseSwitch))
        mouseCard.addRow(SettingRow.make(title: "辅助功能权限", control: permWrap))
        addGroup(col, header: "鼠标中键", card: mouseCard)

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: topAnchor, constant: Design.Layout.contentInset),
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Design.Layout.contentInset)
        ])

        actionHotkey.onChange = { hotkey in settings.actionHotkey = hotkey; onSave(); Toast.show("动作快捷键已更新：\(hotkey.displayText)") }
        panelHotkey.onChange = { hotkey in settings.panelHotkey = hotkey; onSave(); Toast.show("主页快捷键已更新：\(hotkey.displayText)") }
        clipboardDockHotkey.onChange = { hotkey in settings.clipboardDockHotkey = hotkey; onSave(); Toast.show("剪贴板快捷键已更新：\(hotkey.displayText)") }

        refreshPermissionStatus()
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func toggleMouse() {
        settings.middleClickEnabled = mouseSwitch.isOn
        onSave()
        refreshPermissionStatus()
        Toast.show(settings.middleClickEnabled ? "已启用鼠标中键触发" : "已关闭鼠标中键触发")
    }

    @objc private func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        settings.middleClickEnabled = true
        mouseSwitch.setOn(true, animated: true)
        AXIsProcessTrustedWithOptions(options)
        onSave()
        refreshPermissionStatus()
        Toast.show(AXIsProcessTrusted() ? "中键触发已启用" : "授权后请退出并重新打开 Intent Capture。")
    }

    func refreshPermissionStatus() {
        let trusted = AXIsProcessTrusted()
        if !settings.middleClickEnabled {
            permStatus.stringValue = "中键关闭中"
            permStatus.textColor = Design.Color.textTertiary
            permStatus.isHidden = false
            permButton.isHidden = true
        } else if trusted {
            permStatus.stringValue = "已授权"
            permStatus.textColor = Design.Color.accent
            permStatus.isHidden = false
            permButton.isHidden = true
        } else {
            permStatus.isHidden = true
            permButton.isHidden = false
        }
    }
}

// MARK: - 功能（剪贴板 + 区域翻译）

final class FeaturesSectionView: NSView {
    private let clipboardSwitch = GlassSwitch(frame: .zero)
    private let enginePicker = EnginePicker(frame: .zero)
    private let targetLanguage = NSPopUpButton()
    private let apiKey = SecretKeyField(frame: .zero)
    private let debugSwitch = GlassSwitch(frame: .zero)
    private let translationCard = SettingsCard()
    private let keyCard = SettingsCard()
    private let settings: AppSettings
    private let onSave: () -> Void

    private static let languages = ["中文（简体）", "中文（繁体）", "English", "日本語", "한국어"]

    override var isFlipped: Bool { true }

    init(settings: AppSettings, onSave: @escaping () -> Void) {
        self.settings = settings
        self.onSave = onSave
        super.init(frame: .zero)

        let title = pageTitleLabel("功能")
        addSubview(title)
        let col = makeFormColumn(in: self)
        col.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 14).isActive = true

        // 剪贴板
        clipboardSwitch.setOn(settings.clipboardHistoryEnabled, animated: false)
        clipboardSwitch.target = self
        clipboardSwitch.action = #selector(toggleClipboard)
        let clipTile = IconTile(symbol: "clipboard", tint: .white, fill: NSColor(srgbRed: 0.29, green: 0.55, blue: 0.95, alpha: 1), size: 28)
        let clipCard = SettingsCard()
        clipCard.addRow(SettingRow.make(title: "剪贴板拓展坞", control: clipboardSwitch, leading: clipTile, subtitle: "快速查看并复用最近内容"))
        addGroup(col, header: "剪贴板", card: clipCard)

        // 区域翻译
        enginePicker.select(settings.translationEngine)
        enginePicker.onChange = { [weak self] engine in
            guard let self else { return }
            self.settings.translationEngine = engine
            self.rebuildKeyRow()
            self.onSave()
            Toast.show("已切换到\(engine.toggleTitle)")
        }
        enginePicker.translatesAutoresizingMaskIntoConstraints = false
        enginePicker.heightAnchor.constraint(equalToConstant: 40).isActive = true

        var titles = Self.languages
        if !titles.contains(settings.translationTargetLanguage) { titles.insert(settings.translationTargetLanguage, at: 0) }
        targetLanguage.addItems(withTitles: titles)
        targetLanguage.selectItem(withTitle: settings.translationTargetLanguage)
        targetLanguage.target = self
        targetLanguage.action = #selector(save)

        debugSwitch.setOn(settings.translationDebugLogEnabled, animated: false)
        debugSwitch.target = self
        debugSwitch.action = #selector(save)

        apiKey.stringValue = settings.deepSeekAPIKey
        apiKey.placeholderString = "粘贴 API Key（sk-…）"
        apiKey.translatesAutoresizingMaskIntoConstraints = false
        apiKey.widthAnchor.constraint(equalToConstant: 200).isActive = true
        apiKey.heightAnchor.constraint(equalToConstant: 28).isActive = true
        apiKey.onCommit = { [weak self] in self?.save() }

        translationCard.addRow(SettingRow.make(title: "翻译引擎", control: enginePicker))
        translationCard.addRow(SettingRow.make(title: "目标语言", control: targetLanguage))
        translationCard.addRow(SettingRow.make(title: "调试日志", control: debugSwitch))
        addGroup(col, header: "区域翻译", card: translationCard)

        // API Key 作为独立可隐藏卡（A 方案：选中 DeepSeek 才就地展开），避免分隔线插入手术。
        keyCard.addRow(SettingRow.make(title: "API Key", control: apiKey))
        col.addArrangedSubview(keyCard)
        keyCard.leadingAnchor.constraint(equalTo: col.leadingAnchor).isActive = true
        keyCard.trailingAnchor.constraint(equalTo: col.trailingAnchor).isActive = true
        rebuildKeyRow()

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: topAnchor, constant: Design.Layout.contentInset),
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Design.Layout.contentInset)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    /// A 方案：DeepSeek 才展开 API Key 卡。
    private func rebuildKeyRow() {
        keyCard.isHidden = !settings.translationEngine.needsAPIKey
    }

    @objc private func toggleClipboard() {
        settings.clipboardHistoryEnabled = clipboardSwitch.isOn
        onSave()
        Toast.show(settings.clipboardHistoryEnabled ? "已启用剪贴板历史" : "已关闭剪贴板历史")
    }

    @objc private func save() {
        settings.deepSeekAPIKey = apiKey.stringValue
        settings.translationTargetLanguage = targetLanguage.titleOfSelectedItem ?? "中文（简体）"
        settings.translationDebugLogEnabled = debugSwitch.isOn
        enginePicker.reload()
        onSave()
        Toast.show("设置已保存")
    }
}

/// 无字自适应引擎选择：Apple｜DeepSeek 两图标单选，选中加青环；填了 key 显蓝鲸，否则中性图标。
final class EnginePicker: NSView {
    var onChange: ((TranslationEngine) -> Void)?
    private let order: [TranslationEngine] = [.apple, .deepseek]
    private var tiles: [EngineTile] = []
    private var current: TranslationEngine = .apple

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        // 四边都钉：让 EnginePicker 自身宽度=内容宽度，否则会被压成 0 宽、图标落在 bounds 外点不到。
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        for engine in order {
            let tile = EngineTile(engine: engine)
            tile.target = self
            tile.action = #selector(tap(_:))
            tiles.append(tile)
            stack.addArrangedSubview(tile)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func select(_ engine: TranslationEngine) { current = engine; refresh() }
    func reload() { refresh() }

    @objc private func tap(_ sender: EngineTile) {
        guard sender.engine != current else { return }
        current = sender.engine
        refresh()
        onChange?(current)
    }

    private func refresh() { tiles.forEach { $0.setSelected($0.engine == current) } }
}

final class EngineTile: NSControl {
    let engine: TranslationEngine
    private let iconView = NSImageView()
    private var selectedState = false

    init(engine: TranslationEngine) {
        self.engine = engine
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = Design.Radius.tile
        layer?.borderWidth = 1
        translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 54),
            heightAnchor.constraint(equalToConstant: 38),
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 22),
            iconView.heightAnchor.constraint(equalToConstant: 20)
        ])
        updateStyle()
    }

    required init?(coder: NSCoder) { fatalError() }

    func setSelected(_ on: Bool) { selectedState = on; updateStyle() }
    // 子视图（图标/文字）不吞点击：整块 tile 作为原子点击区。
    override func hitTest(_ point: NSPoint) -> NSView? { super.hitTest(point) != nil ? self : nil }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
    override func mouseDown(with event: NSEvent) { sendAction(action, to: target) }

    private func updateStyle() {
        let accent = Design.Color.accent
        // DeepSeek：填了 key 显蓝鲸原图，否则中性 brain；Apple 显 apple.logo。
        switch engine {
        case .apple:
            iconView.image = NSImage(systemSymbolName: "apple.logo", accessibilityDescription: "Apple")?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 17, weight: .medium))
            iconView.contentTintColor = selectedState ? accent : Design.Color.textSecondary
        case .deepseek:
            if !AppSettings.shared.deepSeekAPIKey.isEmpty, let whale = TranslationAsset.image("deepseek1") {
                whale.isTemplate = false
                iconView.image = whale
                iconView.contentTintColor = nil
            } else {
                iconView.image = NSImage(systemSymbolName: "brain", accessibilityDescription: "大模型")?
                    .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 17, weight: .medium))
                iconView.contentTintColor = selectedState ? accent : Design.Color.textSecondary
            }
        }
        layer?.backgroundColor = (selectedState ? accent.withAlphaComponent(0.08) : Design.Color.cardFill).cgColor
        layer?.borderColor = (selectedState ? accent : Design.Color.cardBorder).cgColor
    }
}

// MARK: - 外观

final class AppearanceSectionView: NSView {
    private let settings: AppSettings
    var onAccentChanged: () -> Void = {}
    private let colorWell = NSColorWell()
    private var swatches: [AccentSwatchButton] = []
    private let presets = ["#2EA6C7", "#4C8DFF", "#7C6CF0", "#E0567B",
                           "#E8814A", "#E7B93A", "#3FB56B", "#8A8F98"]

    override var isFlipped: Bool { true }

    init(settings: AppSettings) {
        self.settings = settings
        super.init(frame: .zero)

        let title = pageTitleLabel("外观")
        addSubview(title)
        let col = makeFormColumn(in: self)
        col.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 14).isActive = true

        // 强调色卡：预设色板 + 自定义
        let swatchRow = NSStackView()
        swatchRow.orientation = .horizontal
        swatchRow.spacing = 10
        for hex in presets {
            let swatch = AccentSwatchButton(hex: hex)
            swatch.translatesAutoresizingMaskIntoConstraints = false
            swatch.widthAnchor.constraint(equalToConstant: 28).isActive = true
            swatch.heightAnchor.constraint(equalToConstant: 28).isActive = true
            swatch.target = self
            swatch.action = #selector(pickPreset(_:))
            swatches.append(swatch)
            swatchRow.addArrangedSubview(swatch)
        }
        let swatchWrap = NSView()
        swatchWrap.translatesAutoresizingMaskIntoConstraints = false
        swatchWrap.addSubview(swatchRow)
        swatchRow.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            swatchRow.leadingAnchor.constraint(equalTo: swatchWrap.leadingAnchor, constant: 13),
            swatchRow.trailingAnchor.constraint(lessThanOrEqualTo: swatchWrap.trailingAnchor, constant: -13),
            swatchRow.topAnchor.constraint(equalTo: swatchWrap.topAnchor, constant: 12),
            swatchRow.bottomAnchor.constraint(equalTo: swatchWrap.bottomAnchor, constant: -12)
        ])

        colorWell.color = settings.accentColor
        colorWell.target = self
        colorWell.action = #selector(pickCustom)
        colorWell.translatesAutoresizingMaskIntoConstraints = false
        colorWell.widthAnchor.constraint(equalToConstant: 44).isActive = true
        colorWell.heightAnchor.constraint(equalToConstant: 24).isActive = true

        let accentCard = SettingsCard()
        accentCard.addRow(swatchWrap)
        accentCard.addRow(SettingRow.make(title: "自定义", control: colorWell))
        addGroup(col, header: "强调色", card: accentCard)

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: topAnchor, constant: Design.Layout.contentInset),
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Design.Layout.contentInset)
        ])
        refreshSelection()
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit { NotificationCenter.default.removeObserver(self) }

    // NSColorWell 点过后会一直 active 并绑定系统颜色面板，关窗也不解绑；之后任何 NSApp.activate
    // 都会把颜色面板带回前台。所以设置窗关闭时主动解绑并收起。
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: nil)
        guard let window else { return }
        NotificationCenter.default.addObserver(self, selector: #selector(windowWillClose),
                                               name: NSWindow.willCloseNotification, object: window)
    }

    @objc private func windowWillClose() {
        colorWell.deactivate()
        if NSColorPanel.sharedColorPanelExists, NSColorPanel.shared.isVisible { NSColorPanel.shared.orderOut(nil) }
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

// MARK: - 共享控件

/// 分区大标题。
private func pageTitleLabel(_ text: String) -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.font = Design.Font.pageTitle
    label.textColor = Design.Color.textPrimary
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
}

/// App 风格滑动开关：关=灰底灰钮，开=主题色底白钮，圆角胶囊 + 滑动动画。
final class GlassSwitch: NSControl {
    private let track = CALayer()
    private let knob = CALayer()
    private var accent: NSColor { Design.Color.accent }
    private let offColor = Design.Color.switchOff

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
        knob.frame = CGRect(x: inset, y: inset, width: knobSize, height: knobSize)
        knob.cornerRadius = knobSize / 2
        knob.backgroundColor = NSColor.white.cgColor
        knob.shadowColor = NSColor.black.cgColor
        knob.shadowOpacity = 0.25
        knob.shadowRadius = 1.5
        knob.shadowOffset = CGSize(width: 0, height: -0.5)
        track.addSublayer(knob)
        layer?.addSublayer(track)
        updateAppearance(animated: false)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: trackW, height: trackH) }
    override var acceptsFirstResponder: Bool { true }

    func setOn(_ on: Bool, animated: Bool) { isOn = on; updateAppearance(animated: animated) }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    override func mouseDown(with event: NSEvent) {
        setOn(!isOn, animated: true)
        sendAction(action, to: target)
    }

    private func updateAppearance(animated: Bool) {
        let knobX = isOn ? trackW - inset - knobSize : inset
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        if animated { CATransaction.setAnimationDuration(Design.Motion.switchDuration) }
        track.backgroundColor = (isOn ? accent : offColor).cgColor
        knob.frame.origin.x = knobX
        CATransaction.commit()
    }
}

/// 带小眼睛显隐的 API Key 输入框：默认遮住，点眼睛切明文；玻璃容器 + 聚焦动画。
final class SecretKeyField: NSView {
    var onCommit: (() -> Void)?
    var placeholderString: String? {
        didSet { plain.placeholderString = placeholderString; secure.placeholderString = placeholderString }
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
    private var accent: NSColor { Design.Color.accent }

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
                field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
                field.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -32),
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

    private func updateChrome(animated: Bool) {
        let border = (focused ? accent.withAlphaComponent(0.9) : Design.Color.cardBorder).cgColor
        let bg = (focused ? NSColor.black.withAlphaComponent(0.02) : NSColor.black.withAlphaComponent(0.03)).cgColor
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

/// 单行、无边框、透明底输入框，聚焦回调（供 SecretKeyField 画容器）。
final class BareTextField: NSTextField {
    var onFocusChange: ((Bool) -> Void)?
    override init(frame frameRect: NSRect) { super.init(frame: frameRect); setupBare() }
    required init?(coder: NSCoder) { super.init(coder: coder); setupBare() }
    private func setupBare() {
        isBordered = false; drawsBackground = false; focusRingType = .none
        font = .systemFont(ofSize: 12, weight: .medium); textColor = .labelColor
        usesSingleLineMode = true; lineBreakMode = .byClipping; cell?.wraps = false; cell?.isScrollable = true
    }
    override func becomeFirstResponder() -> Bool { let ok = super.becomeFirstResponder(); if ok { onFocusChange?(true) }; return ok }
    override func textDidEndEditing(_ notification: Notification) { super.textDidEndEditing(notification); onFocusChange?(false) }
}

/// 单行密文版本。
final class BareSecureField: NSSecureTextField {
    var onFocusChange: ((Bool) -> Void)?
    override init(frame frameRect: NSRect) { super.init(frame: frameRect); setupBare() }
    required init?(coder: NSCoder) { super.init(coder: coder); setupBare() }
    private func setupBare() {
        isBordered = false; drawsBackground = false; focusRingType = .none
        font = .systemFont(ofSize: 12, weight: .medium); textColor = .labelColor
        usesSingleLineMode = true; lineBreakMode = .byClipping; cell?.wraps = false; cell?.isScrollable = true
    }
    override func becomeFirstResponder() -> Bool { let ok = super.becomeFirstResponder(); if ok { onFocusChange?(true) }; return ok }
    override func textDidEndEditing(_ notification: Notification) { super.textDidEndEditing(notification); onFocusChange?(false) }
}

/// 主题色预设色板：圆角色块，选中时描一圈青环。
final class AccentSwatchButton: NSButton {
    let hex: String
    var isCurrent = false { didSet { needsDisplay = true } }

    init(hex: String) {
        self.hex = hex
        super.init(frame: .zero)
        title = ""; isBordered = false; wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 3, dy: 3)
        let path = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)
        (NSColor(hexString: hex) ?? .gray).setFill()
        path.fill()
        if isCurrent {
            let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 9, yRadius: 9)
            Design.Color.accent.setStroke()
            ring.lineWidth = 2
            ring.stroke()
        }
    }
}

/// 文本输入框：去系统 bezel，换成浅灰底 + hairline 描边，聚焦转主题色。
final class GlassTextField: NSTextField {
    override init(frame frameRect: NSRect) { super.init(frame: frameRect); setup() }
    required init?(coder: NSCoder) { super.init(coder: coder); setup() }

    private func setup() {
        isBordered = false; drawsBackground = false; focusRingType = .none
        font = .systemFont(ofSize: 12, weight: .medium)
        textColor = Design.Color.textPrimary
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.03).cgColor
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.borderColor = Design.Color.cardBorder.cgColor
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result { layer?.borderColor = Design.Color.accent.withAlphaComponent(0.7).cgColor }
        return result
    }

    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        layer?.borderColor = Design.Color.cardBorder.cgColor
    }
}

/// 强调色描边按钮：用于需要用户主动触发的动作（如授权）。
final class AccentGhostButton: NSButton {
    private var accent: NSColor { Design.Color.accent }

    init(title: String) {
        super.init(frame: .zero)
        self.title = title
        isBordered = false; wantsLayer = true
        font = .systemFont(ofSize: 12, weight: .semibold)
    }

    required init?(coder: NSCoder) { fatalError() }

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

// MARK: - CaptureAction 图标

private extension CaptureAction {
    var symbolName: String {
        switch self {
        case .screenshotCopy: return "camera.viewfinder"
        case .screenshotSave: return "square.and.arrow.down"
        case .screenshotSaveAndCopy: return "doc.on.clipboard"
        case .ocrCopy: return "text.viewfinder"
        case .translate: return "character.bubble"
        case .pickColor: return "eyedropper"
        }
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
