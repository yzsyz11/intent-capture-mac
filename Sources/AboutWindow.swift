import AppKit

/// 「关于」面板：展示 app 身份、版本与**原作者署名**（归属 / 防伪标识）。
/// 成品里始终带着作者信息与仓库出处，配合 MIT 的强制署名条款，防止被冒名为原作者。
final class AboutWindow: NSWindow {
    static let author = "yzsyz11"
    static let repoURL = "https://github.com/yzsyz11/intent-capture-mac"

    init() {
        super.init(
            contentRect: CGRect(x: 0, y: 0, width: 340, height: 360),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        title = "关于 Intent Capture"
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        appearance = NSAppearance(named: .aqua)
        backgroundColor = .white
        contentView = AboutContentView()
    }

    required init?(coder: NSCoder) { fatalError() }

    func present() {
        center()
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

final class AboutContentView: NSView {
    override var isFlipped: Bool { true }

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 340, height: 360))
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.cgColor
        build()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let buildNo = info?["CFBundleVersion"] as? String ?? "?"

        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.wantsLayer = true
        icon.layer?.cornerRadius = 16
        icon.layer?.masksToBounds = true
        icon.translatesAutoresizingMaskIntoConstraints = false

        let name = label("Intent Capture", size: 20, weight: .semibold, color: Design.Color.textPrimary)
        let tagline = label("中键长按环形取词 · 截图 · 取色 · OCR · 区域翻译", size: 12, weight: .regular, color: Design.Color.textSecondary)
        tagline.alignment = .center
        tagline.maximumNumberOfLines = 2
        let versionLabel = label("版本 \(version) (\(buildNo))", size: 12, weight: .regular, color: Design.Color.textTertiary)

        let divider = NSView()
        divider.wantsLayer = true
        divider.layer?.backgroundColor = Design.Color.separator.cgColor
        divider.translatesAutoresizingMaskIntoConstraints = false

        let author = label("原作者 · \(AboutWindow.author)", size: 13, weight: .medium, color: Design.Color.textPrimary)
        let copyright = label("© 2026 \(AboutWindow.author)　保留署名权", size: 12, weight: .regular, color: Design.Color.textSecondary)

        let repo = LinkTextButton(title: AboutWindow.repoURL)
        repo.target = self
        repo.action = #selector(openRepo)
        repo.translatesAutoresizingMaskIntoConstraints = false

        [icon, name, tagline, versionLabel, divider, author, copyright, repo].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        NSLayoutConstraint.activate([
            icon.topAnchor.constraint(equalTo: topAnchor, constant: 30),
            icon.centerXAnchor.constraint(equalTo: centerXAnchor),
            icon.widthAnchor.constraint(equalToConstant: 68),
            icon.heightAnchor.constraint(equalToConstant: 68),

            name.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 14),
            name.centerXAnchor.constraint(equalTo: centerXAnchor),

            tagline.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 6),
            tagline.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            tagline.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),

            versionLabel.topAnchor.constraint(equalTo: tagline.bottomAnchor, constant: 8),
            versionLabel.centerXAnchor.constraint(equalTo: centerXAnchor),

            divider.topAnchor.constraint(equalTo: versionLabel.bottomAnchor, constant: 18),
            divider.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 40),
            divider.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -40),
            divider.heightAnchor.constraint(equalToConstant: 1),

            author.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 16),
            author.centerXAnchor.constraint(equalTo: centerXAnchor),

            copyright.topAnchor.constraint(equalTo: author.bottomAnchor, constant: 6),
            copyright.centerXAnchor.constraint(equalTo: centerXAnchor),

            repo.topAnchor.constraint(equalTo: copyright.bottomAnchor, constant: 10),
            repo.centerXAnchor.constraint(equalTo: centerXAnchor)
        ])
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: size, weight: weight)
        l.textColor = color
        l.alignment = .center
        return l
    }

    @objc private func openRepo() {
        if let url = URL(string: AboutWindow.repoURL) {
            NSWorkspace.shared.open(url)
        }
    }
}

/// 强调色文字链按钮（用于仓库地址）。
final class LinkTextButton: NSButton {
    init(title: String) {
        super.init(frame: .zero)
        self.title = title
        isBordered = false
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: Design.Color.accent,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        let text = NSString(string: title)
        let size = text.size(withAttributes: attrs)
        text.draw(at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attrs)
    }

    override var intrinsicContentSize: NSSize {
        let s = NSString(string: title).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12)])
        return NSSize(width: s.width + 4, height: s.height + 4)
    }
}
