import AppKit

/// 3 步权限引导向导：首次启动或装了新版且有权限未生效时弹出。
///
/// 布局对齐设计稿 v3：顶部 app 图标 → 标题 → 大号分段进度 → 两项权限行 → 重启提示 → 完成 / 稍后。
/// 通过内置 `PermissionWatcher` 实时轮询：用户在系统设置里一授权，行状态自动翻绿、进度自动前进，
/// 无需切回来点。按钮统一走 `onHeal`（= AppDelegate 的三态自愈流程，单一真相源）。
final class OnboardingWindow: NSWindow {
    private let content: OnboardingContentView
    /// 用户点「完成 / 稍后」主动关闭时触发（重启导致的终止不走这里，故不会清掉恢复标记）。
    var onDismiss: (() -> Void)?

    init(onGranted: @escaping (PermissionKind) -> Void) {
        content = OnboardingContentView(onGranted: onGranted)
        super.init(
            contentRect: CGRect(x: 0, y: 0, width: 400, height: 520),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        title = "Intent Capture"
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        appearance = NSAppearance(named: .aqua)
        backgroundColor = .white
        contentView = content
        content.onFinish = { [weak self] in self?.close() }
    }

    required init?(coder: NSCoder) { fatalError() }

    func present() {
        content.startWatching()
        center()
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    override func close() {
        content.stopWatching()
        onDismiss?()
        super.close()
    }
}

// MARK: - 内容视图

final class OnboardingContentView: NSView {
    var onFinish: (() -> Void)?
    /// 某权限授权到手且已在向导里翻绿后回调（AppDelegate 据此启用中键 / 提示屏幕录制重启）。
    private let onGranted: (PermissionKind) -> Void

    private let progressLabel = NSTextField(labelWithString: "")
    private let segments: [NSView] = [NSView(), NSView()]
    private let rows: [PermissionRowView]
    private let finishButton = NSButton()
    private var watcher: PermissionWatcher?

    private var revealed: Set<PermissionKind> = []   // 已翻绿显示的行
    private var initialized = false                   // 首帧：打开时已授权的行直接显示绿，无动画/无侧效应

    override var isFlipped: Bool { true }

    init(onGranted: @escaping (PermissionKind) -> Void) {
        self.onGranted = onGranted
        rows = [
            PermissionRowView(kind: .accessibility, symbol: "computermouse", subtitle: "中键短按 · 长按环形菜单"),
            PermissionRowView(kind: .screenRecording, symbol: "camera.viewfinder", subtitle: "截图 · 取色 · OCR")
        ]
        super.init(frame: CGRect(x: 0, y: 0, width: 400, height: 520))
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.cgColor
        build()
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        let inset: CGFloat = 30

        // 顶部 app 图标
        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.wantsLayer = true
        icon.layer?.cornerRadius = 17
        icon.layer?.masksToBounds = true
        icon.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "开启完整功能")
        title.font = .systemFont(ofSize: 21, weight: .semibold)
        title.textColor = Design.Color.textPrimary
        title.alignment = .center
        title.translatesAutoresizingMaskIntoConstraints = false

        // 进度：已完成 N / 2 + 分段条
        progressLabel.font = .systemFont(ofSize: 14)
        progressLabel.translatesAutoresizingMaskIntoConstraints = false
        let segStack = NSStackView(views: segments)
        segStack.orientation = .horizontal
        segStack.distribution = .fillEqually
        segStack.spacing = 6
        segStack.translatesAutoresizingMaskIntoConstraints = false
        for s in segments {
            s.wantsLayer = true
            s.layer?.cornerRadius = 3.5
            s.heightAnchor.constraint(equalToConstant: 7).isActive = true
        }

        // 权限卡
        let card = NSView()
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.white.cgColor
        card.layer?.cornerRadius = 12
        card.layer?.borderWidth = 1
        card.layer?.borderColor = Design.Color.cardBorder.cgColor
        card.translatesAutoresizingMaskIntoConstraints = false
        let separator = NSView()
        separator.wantsLayer = true
        separator.layer?.backgroundColor = Design.Color.separator.cgColor
        separator.translatesAutoresizingMaskIntoConstraints = false
        for r in rows {
            r.translatesAutoresizingMaskIntoConstraints = false
            r.onAction = { [weak self] kind in self?.initiate(kind) }
            card.addSubview(r)
        }
        card.addSubview(separator)

        // 重启提示
        let hint = NSTextField(wrappingLabelWithString: "授权后自动前进；屏幕录制需重启一次，向导会自动为你重启。")
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = Design.Color.textTertiary
        hint.translatesAutoresizingMaskIntoConstraints = false

        // 完成按钮
        finishButton.title = "完成"
        finishButton.bezelStyle = .rounded
        finishButton.controlSize = .large
        finishButton.font = .systemFont(ofSize: 14, weight: .medium)
        finishButton.target = self
        finishButton.action = #selector(finishTapped)
        finishButton.translatesAutoresizingMaskIntoConstraints = false

        let later = LinkButton(title: "稍后再说")
        later.target = self
        later.action = #selector(finishTapped)
        later.translatesAutoresizingMaskIntoConstraints = false

        [icon, title, progressLabel, segStack, card, hint, finishButton, later].forEach(addSubview)

        NSLayoutConstraint.activate([
            icon.topAnchor.constraint(equalTo: topAnchor, constant: 30),
            icon.centerXAnchor.constraint(equalTo: centerXAnchor),
            icon.widthAnchor.constraint(equalToConstant: 72),
            icon.heightAnchor.constraint(equalToConstant: 72),

            title.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 16),
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            title.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),

            progressLabel.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 22),
            progressLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            progressLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),

            segStack.topAnchor.constraint(equalTo: progressLabel.bottomAnchor, constant: 9),
            segStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            segStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),

            card.topAnchor.constraint(equalTo: segStack.bottomAnchor, constant: 24),
            card.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            card.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),

            rows[0].topAnchor.constraint(equalTo: card.topAnchor),
            rows[0].leadingAnchor.constraint(equalTo: card.leadingAnchor),
            rows[0].trailingAnchor.constraint(equalTo: card.trailingAnchor),
            separator.topAnchor.constraint(equalTo: rows[0].bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 70),
            separator.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),
            rows[1].topAnchor.constraint(equalTo: separator.bottomAnchor),
            rows[1].leadingAnchor.constraint(equalTo: card.leadingAnchor),
            rows[1].trailingAnchor.constraint(equalTo: card.trailingAnchor),
            rows[1].bottomAnchor.constraint(equalTo: card.bottomAnchor),

            hint.topAnchor.constraint(equalTo: card.bottomAnchor, constant: 12),
            hint.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset + 4),
            hint.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset - 4),

            finishButton.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 20),
            finishButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            finishButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            finishButton.heightAnchor.constraint(equalToConstant: 36),

            later.topAnchor.constraint(equalTo: finishButton.bottomAnchor, constant: 10),
            later.centerXAnchor.constraint(equalTo: centerXAnchor)
        ])
    }

    // MARK: 点「去授权 / 一键修复」→ 只负责发起（清僵尸 + 拉授权 + 开系统设置页）。
    // 拿到授权后的"切回窗口 + 翻绿"由 watcher 统一处理，保证用户正看着向导时才变对号。

    private func initiate(_ kind: PermissionKind) {
        let state = PermissionEvaluator.state(of: kind)
        guard state != .granted else { return }
        Toast.show("请在系统设置中允许\(kind.displayName)，向导会等待并自动打勾。")
        PermissionHealer.heal(kind, state: state)
        // 进入等待态：转圈直到 watcher 侦测到授权成功再翻绿。
        rows.first { $0.kind == kind }?.showPending()
    }

    // MARK: 轮询与刷新

    func startWatching() {
        watcher = PermissionWatcher { [weak self] _ in self?.refresh() }
        watcher?.start()
    }

    func stopWatching() {
        watcher?.stop()
        watcher = nil
    }

    private func refresh() {
        for row in rows {
            let state = PermissionEvaluator.state(of: row.kind)
            if state == .granted {
                if revealed.contains(row.kind) { continue }  // 已绿，别重复触发
                revealed.insert(row.kind)
                // 向导始终开着：不关系统设置页、不动窗口，只原地把这行翻绿。
                if initialized {
                    // 会话期间刚拿到授权：带动画翻绿 + 授权后侧效应（启用中键 / 屏幕录制先绿再重启）。
                    row.revealGranted()
                    onGranted(row.kind)
                } else {
                    // 打开向导时就已授权：直接显示绿，不做动画、不触发侧效应。
                    row.update(state: .granted)
                }
            } else {
                revealed.remove(row.kind)
                row.update(state: state)
            }
        }
        initialized = true
        updateProgress()
    }

    private func updateProgress() {
        let grantedCount = revealed.count
        let total = rows.count
        let attr = NSMutableAttributedString(
            string: "已完成 ",
            attributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: Design.Color.textSecondary]
        )
        attr.append(NSAttributedString(
            string: "\(grantedCount)",
            attributes: [.font: NSFont.systemFont(ofSize: 22, weight: .medium), .foregroundColor: Design.Color.accent]
        ))
        attr.append(NSAttributedString(
            string: " / \(total)",
            attributes: [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: Design.Color.textSecondary]
        ))
        progressLabel.attributedStringValue = attr

        for (i, seg) in segments.enumerated() {
            seg.layer?.backgroundColor = (i < grantedCount ? Design.Color.accent : Design.Color.switchOff.withAlphaComponent(0.15)).cgColor
        }

        let allGranted = grantedCount == total
        finishButton.isEnabled = allGranted
        finishButton.keyEquivalent = allGranted ? "\r" : ""
    }

    @objc private func finishTapped() {
        onFinish?()
    }
}

// MARK: - 权限行

final class PermissionRowView: NSView {
    let kind: PermissionKind
    var onAction: ((PermissionKind) -> Void)?

    private let tile = NSView()
    private let iconView = NSImageView()
    private let trailingContainer = NSView()
    private let checkView = NSImageView()
    private let actionButton = AccentFilledButton(title: "去授权")
    private let spinner = NSProgressIndicator()
    private let pendingLabel = NSTextField(labelWithString: "等待授权")
    private lazy var pendingStack = NSStackView(views: [pendingLabel, spinner])

    /// 尾部三态显示：按钮（去授权/一键修复）/ 等待授权（转圈）/ 绿色对号。
    private enum Trailing { case button, pending, check }
    private var isPending = false

    override var isFlipped: Bool { true }

    init(kind: PermissionKind, symbol: String, subtitle: String) {
        self.kind = kind
        super.init(frame: .zero)

        tile.wantsLayer = true
        tile.layer?.cornerRadius = 11
        tile.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        tile.addSubview(iconView)

        let titleLabel = NSTextField(labelWithString: kind.displayName)
        titleLabel.font = .systemFont(ofSize: 14, weight: .medium)
        titleLabel.textColor = Design.Color.textPrimary
        let subLabel = NSTextField(labelWithString: subtitle)
        subLabel.font = .systemFont(ofSize: 12)
        subLabel.textColor = Design.Color.textSecondary
        let textStack = NSStackView(views: [titleLabel, subLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false

        checkView.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "已生效")
        checkView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 22, weight: .regular)
        checkView.contentTintColor = .systemGreen
        checkView.wantsLayer = true
        checkView.translatesAutoresizingMaskIntoConstraints = false
        actionButton.target = self
        actionButton.action = #selector(actionTapped)
        actionButton.translatesAutoresizingMaskIntoConstraints = false

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.translatesAutoresizingMaskIntoConstraints = false
        pendingLabel.font = .systemFont(ofSize: 12)
        pendingLabel.textColor = Design.Color.textSecondary
        pendingStack.orientation = .horizontal
        pendingStack.spacing = 6
        pendingStack.alignment = .centerY
        pendingStack.isHidden = true
        pendingStack.translatesAutoresizingMaskIntoConstraints = false

        trailingContainer.translatesAutoresizingMaskIntoConstraints = false
        trailingContainer.addSubview(checkView)
        trailingContainer.addSubview(actionButton)
        trailingContainer.addSubview(pendingStack)

        [tile, textStack, trailingContainer].forEach(addSubview)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 70),
            tile.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            tile.centerYAnchor.constraint(equalTo: centerYAnchor),
            tile.widthAnchor.constraint(equalToConstant: 40),
            tile.heightAnchor.constraint(equalToConstant: 40),
            iconView.centerXAnchor.constraint(equalTo: tile.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: tile.centerYAnchor),

            textStack.leadingAnchor.constraint(equalTo: tile.trailingAnchor, constant: 14),
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),

            trailingContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            trailingContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
            trailingContainer.widthAnchor.constraint(greaterThanOrEqualToConstant: 24),
            trailingContainer.heightAnchor.constraint(equalToConstant: 30),
            checkView.trailingAnchor.constraint(equalTo: trailingContainer.trailingAnchor),
            checkView.centerYAnchor.constraint(equalTo: trailingContainer.centerYAnchor),
            actionButton.trailingAnchor.constraint(equalTo: trailingContainer.trailingAnchor),
            actionButton.centerYAnchor.constraint(equalTo: trailingContainer.centerYAnchor),
            actionButton.heightAnchor.constraint(equalToConstant: 28),
            actionButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 72),
            pendingStack.trailingAnchor.constraint(equalTo: trailingContainer.trailingAnchor),
            pendingStack.centerYAnchor.constraint(equalTo: trailingContainer.centerYAnchor),
            trailingContainer.leadingAnchor.constraint(greaterThanOrEqualTo: textStack.trailingAnchor, constant: 10)
        ])
    }

    /// 进入"等待授权"态：点了「去授权」后显示转圈，直到 watcher 侦测到真的授权成功。
    func showPending() {
        isPending = true
        setTrailing(.pending)
    }

    private func setTrailing(_ mode: Trailing) {
        actionButton.isHidden = mode != .button
        pendingStack.isHidden = mode != .pending
        checkView.isHidden = mode != .check
        if mode == .pending { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
    }

    required init?(coder: NSCoder) { fatalError() }

    /// 授权成功后翻绿：图标块淡入绿色、对号带弹性缩放蹦出来（绕中心），让变化不生硬。
    func revealGranted() {
        isPending = false
        tile.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.14).cgColor
        iconView.contentTintColor = .systemGreen
        setTrailing(.check)

        guard let layer = checkView.layer else { return }
        layoutSubtreeIfNeeded()                          // 确保 frame 已定，anchorPoint 换算才准
        let f = checkView.frame
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.position = CGPoint(x: f.midX, y: f.midY)   // 补偿 anchorPoint 变化，保持居中

        let pop = CASpringAnimation(keyPath: "transform.scale")
        pop.fromValue = 0.3
        pop.toValue = 1.0
        pop.damping = 11
        pop.stiffness = 210
        pop.initialVelocity = 9
        pop.duration = pop.settlingDuration
        layer.add(pop, forKey: "pop")

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.2
        layer.add(fade, forKey: "fade")
    }

    func update(state: PermissionState) {
        switch state {
        case .granted:
            isPending = false
            tile.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.14).cgColor
            iconView.contentTintColor = .systemGreen
            setTrailing(.check)
        case .notGranted, .stale:
            tile.layer?.backgroundColor = Design.Color.accentTint(0.12).cgColor
            iconView.contentTintColor = Design.Color.accent
            actionButton.title = (state == .stale) ? "一键修复" : "去授权"
            actionButton.needsDisplay = true
            // 已在等待态就保持转圈（别被每 0.5s 的轮询打回按钮），否则显示按钮。
            setTrailing(isPending ? .pending : .button)
        }
    }

    @objc private func actionTapped() {
        onAction?(kind)
    }
}

// MARK: - 小组件

/// 实心强调色按钮（设计稿里的「去授权 / 一键修复」）。
final class AccentFilledButton: NSButton {
    init(title: String) {
        super.init(frame: .zero)
        self.title = title
        isBordered = false
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let accent = Design.Color.accent
        let path = NSBezierPath(roundedRect: bounds, xRadius: 9, yRadius: 9)
        accent.withAlphaComponent(isHighlighted ? 0.82 : 1).setFill()
        path.fill()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let text = NSString(string: title)
        let size = text.size(withAttributes: attrs)
        text.draw(at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attrs)
    }
}

/// 文字链按钮（「稍后再说」）。
final class LinkButton: NSButton {
    init(title: String) {
        super.init(frame: .zero)
        self.title = title
        isBordered = false
        wantsLayer = true
        font = .systemFont(ofSize: 13)
        contentTintColor = Design.Color.textSecondary
    }
    required init?(coder: NSCoder) { fatalError() }
}
