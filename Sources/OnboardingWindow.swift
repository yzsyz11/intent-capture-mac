import AppKit

/// 3 步权限引导向导：首次启动或装了新版且有权限未生效时弹出。
///
/// 布局对齐设计稿 v3：顶部 app 图标 → 标题 → 大号分段进度 → 两项权限行 → 重启提示 → 完成 / 稍后。
/// 通过内置 `PermissionWatcher` 实时轮询：用户在系统设置里一授权，行状态自动翻绿、进度自动前进，
/// 无需切回来点。按钮统一走 `onHeal`（= AppDelegate 的三态自愈流程，单一真相源）。
final class OnboardingWindow: NSWindow {
    private let content: OnboardingContentView

    init(onHeal: @escaping (PermissionKind) -> Void) {
        content = OnboardingContentView(onHeal: onHeal)
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
        super.close()
    }
}

// MARK: - 内容视图

final class OnboardingContentView: NSView {
    var onFinish: (() -> Void)?
    private let onHeal: (PermissionKind) -> Void

    private let progressLabel = NSTextField(labelWithString: "")
    private let segments: [NSView] = [NSView(), NSView()]
    private let rows: [PermissionRowView]
    private let finishButton = NSButton()
    private var watcher: PermissionWatcher?

    override var isFlipped: Bool { true }

    init(onHeal: @escaping (PermissionKind) -> Void) {
        self.onHeal = onHeal
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
            r.onAction = { [weak self] kind in self?.onHeal(kind) }
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
        var grantedCount = 0
        for row in rows {
            let state = PermissionEvaluator.state(of: row.kind)
            row.update(state: state)
            if state == .granted { grantedCount += 1 }
        }
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
        checkView.translatesAutoresizingMaskIntoConstraints = false
        actionButton.target = self
        actionButton.action = #selector(actionTapped)
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        trailingContainer.translatesAutoresizingMaskIntoConstraints = false
        trailingContainer.addSubview(checkView)
        trailingContainer.addSubview(actionButton)

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
            trailingContainer.leadingAnchor.constraint(greaterThanOrEqualTo: textStack.trailingAnchor, constant: 10)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(state: PermissionState) {
        switch state {
        case .granted:
            tile.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.14).cgColor
            iconView.contentTintColor = .systemGreen
            checkView.isHidden = false
            actionButton.isHidden = true
        case .notGranted, .stale:
            tile.layer?.backgroundColor = Design.Color.accentTint(0.12).cgColor
            iconView.contentTintColor = Design.Color.accent
            checkView.isHidden = true
            actionButton.isHidden = false
            actionButton.title = (state == .stale) ? "一键修复" : "去授权"
            actionButton.needsDisplay = true
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
