import AppKit

/// 主页 UI 的设计令牌：白底原生风格的单一真实源。
/// 间距、圆角、字体、颜色集中一处，配合 FormStack / 组件库使用；改一处即全局生效。
enum Design {

    /// 间距刻度（8pt 节奏）。所有留白落在这套刻度上，保证纵向节奏统一。
    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24   // 内容区 / 卡片外边距
    }

    /// 圆角。
    enum Radius {
        static let card: CGFloat = 12    // 设置分组卡
        static let nav: CGFloat = 9      // 侧边栏项 / 选中滑块
        static let tile: CGFloat = 8     // 图标块
        static let action: CGFloat = 12  // 动作宫格
    }

    /// 固定尺寸（窗口 680×420 不可缩放）。
    enum Layout {
        static let windowWidth: CGFloat = 680
        static let windowHeight: CGFloat = 420
        static let sidebarWidth: CGFloat = 188
        static let contentWidth: CGFloat = windowWidth - sidebarWidth   // 492
        static let contentInset: CGFloat = Spacing.xxl                   // 24
        static let cardWidth: CGFloat = contentWidth - contentInset * 2  // 444
        static let rowHeight: CGFloat = 30
        static let navItemHeight: CGFloat = 32
        static let navItemGap: CGFloat = 4
        static let statusBarHeight: CGFloat = 54
    }

    /// 字体。
    enum Font {
        static let pageTitle = NSFont.systemFont(ofSize: 17, weight: .semibold)  // 分区大标题
        static let groupHeader = NSFont.systemFont(ofSize: 11.5, weight: .medium) // 分组小标题
        static let rowTitle = NSFont.systemFont(ofSize: 13)
        static let rowLabel = NSFont.systemFont(ofSize: 12.5)
        static let secondary = NSFont.systemFont(ofSize: 11.5)
    }

    /// 颜色（白底浅色语义）。窗口浅灰白 + 纯白卡，卡靠 hairline 描边 + 轻阴影出层次；冷青强调。
    enum Color {
        /// 窗口底：极浅中性灰白（系统设置同款，让纯白卡片浮起来）。
        static let windowBackground = NSColor(white: 0.96, alpha: 1)
        /// 卡片填充：纯白。
        static let cardFill = NSColor.white
        static let cardBorder = NSColor.black.withAlphaComponent(0.09)
        static let separator = NSColor.black.withAlphaComponent(0.07)
        static let textPrimary = NSColor(white: 0.12, alpha: 1)
        static let textSecondary = NSColor.black.withAlphaComponent(0.55)
        static let textTertiary = NSColor.black.withAlphaComponent(0.4)
        /// 下沉状态条：微凹。
        static let statusBarFill = NSColor.black.withAlphaComponent(0.035)
        static let sidebarFill = NSColor.black.withAlphaComponent(0.025)
        static let tileFill = NSColor.black.withAlphaComponent(0.05)
        static let switchOff = NSColor.black.withAlphaComponent(0.18)

        static var accent: NSColor { AppSettings.shared.accentColor }
        static func accentTint(_ a: CGFloat) -> NSColor { accent.withAlphaComponent(a) }
    }

    /// 动效参数（弹簧，按 apple-design：临界阻尼、response≈0.35）。
    enum Motion {
        static let pageResponse: Double = 0.35
        static let switchDuration: Double = 0.24
        static var reduceMotion: Bool {
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }
    }
}

/// 全局反馈语气：主 Toast 与剪贴板 Dock 胶囊共用的单一颜色/图标真相源。
/// 取代此前 Toast 的关键词猜色和 Dock 各自一套枚举。
enum FeedbackTone {
    case success   // 已完成：复制 / 保存 / 更新 / 开启 / 切换
    case info      // 中性：操作指引、进行中
    case warning   // 需留意：空结果、需用户处理
    case danger    // 失败 / 已取消
    case delete    // 删除（红色，垃圾桶图标）

    var color: NSColor {
        switch self {
        case .success: return .systemGreen
        case .info: return .systemBlue
        case .warning: return .systemOrange
        case .danger, .delete: return .systemRed
        }
    }

    var symbolName: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .danger: return "xmark.circle.fill"
        case .delete: return "trash.circle.fill"
        }
    }
}
