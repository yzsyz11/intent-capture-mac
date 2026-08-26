import AppKit

/// 白底原生风格的可复用组件库。全部基于 Auto Layout，天生弹性——增删、重排行几乎零成本，
/// 取代旧的 placeRow / GlassSectionCard 手打坐标写法。配合 Design 令牌使用。

/// 分组小标题（macOS 系统设置那种贴在卡片外的灰色小字）。
final class GroupHeader: NSTextField {
    init(_ text: String) {
        super.init(frame: .zero)
        stringValue = text
        font = Design.Font.groupHeader
        textColor = Design.Color.textTertiary
        isEditable = false
        isBordered = false
        drawsBackground = false
        translatesAutoresizingMaskIntoConstraints = false
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// 圆角图标块：放 SF Symbol 或图片。默认中性底，可传彩色底（系统设置行首图标那种）。
final class IconTile: NSView {
    init(symbol: String, tint: NSColor = Design.Color.textSecondary,
         fill: NSColor = Design.Color.tileFill, size: CGFloat = 28, pointSize: CGFloat = 16) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = Design.Radius.tile
        layer?.backgroundColor = fill.cgColor
        translatesAutoresizingMaskIntoConstraints = false

        let iv = NSImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        let cfg = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        iv.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg)
        iv.contentTintColor = tint
        iv.imageScaling = .scaleProportionallyDown
        addSubview(iv)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: size),
            heightAnchor.constraint(equalToConstant: size),
            iv.centerXAnchor.constraint(equalTo: centerXAnchor),
            iv.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// 设置分组卡：白底 + hairline 描边 + 轻阴影，内部竖直堆叠行，行间自动插入分隔线。
final class SettingsCard: NSView {
    private let stack = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = Design.Color.cardFill.cgColor
        layer?.cornerRadius = Design.Radius.card
        layer?.borderWidth = 0.5
        layer?.borderColor = Design.Color.cardBorder.cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.06
        layer?.shadowRadius = 8
        layer?.shadowOffset = CGSize(width: 0, height: -2)

        stack.orientation = .vertical
        stack.spacing = 0
        stack.distribution = .fill
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
    convenience init() { self.init(frame: .zero); translatesAutoresizingMaskIntoConstraints = false }

    /// 追加一行。非首行时自动在上方插入通栏分隔线。
    /// 注意：约束必须在视图加入层级「之后」再激活，否则无共同祖先会抛 NSException。
    func addRow(_ row: NSView) {
        if !stack.arrangedSubviews.isEmpty {
            let line = NSView()
            line.wantsLayer = true
            line.layer?.backgroundColor = Design.Color.separator.cgColor
            line.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(line)
            line.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
            line.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        row.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
}

/// 一行「左说明 + 右控件」，两端对齐，含标准内边距。
enum SettingRow {
    static func make(title: String, control: NSView,
                     leading: NSView? = nil, subtitle: String? = nil) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = label(title, font: Design.Font.rowTitle, color: Design.Color.textPrimary)
        let textStack = NSStackView(views: [titleLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 1
        if let subtitle {
            textStack.addArrangedSubview(label(subtitle, font: Design.Font.secondary, color: Design.Color.textTertiary))
        }
        textStack.translatesAutoresizingMaskIntoConstraints = false

        let h = NSStackView()
        h.orientation = .horizontal
        h.alignment = .centerY
        h.spacing = 12
        h.translatesAutoresizingMaskIntoConstraints = false
        if let leading { h.addArrangedSubview(leading) }
        h.addArrangedSubview(textStack)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        h.addArrangedSubview(spacer)
        control.translatesAutoresizingMaskIntoConstraints = false
        h.addArrangedSubview(control)

        row.addSubview(h)
        NSLayoutConstraint.activate([
            h.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 13),
            h.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -13),
            h.topAnchor.constraint(equalTo: row.topAnchor, constant: 10),
            h.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -10),
            spacer.widthAnchor.constraint(greaterThanOrEqualToConstant: 8)
        ])
        return row
    }

    static func label(_ text: String, font: NSFont, color: NSColor) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = font
        l.textColor = color
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }
}
