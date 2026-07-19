import SwiftUI
import UIKit

/// MEditor 移动端「纸墨」设计系统：宣纸白 · 松烟墨 · 朱砂印。
/// 全 App 的颜色 / 字体 / 圆角 / 间距统一从这里取，不在各视图散落字面量。
enum PaperTheme {

    // MARK: - 颜色

    /// 色板原始值：Color 与 JS 用 hex 字符串（Hex）均由此派生，改一处全局同步。
    /// 真正的中式纸墨不是暖黄配焦橙——宣纸是带青灰的冷白，松烟墨是蓝黑，
    /// 全页唯一的亮色是落款那枚朱砂印。
    private enum Palette {
        static let paper: UInt32          = 0xF4F5F2
        static let card: UInt32           = 0xFCFCFA
        static let ink: UInt32            = 0x1B2434
        static let inkSecondary: UInt32   = 0x5D6673
        static let accent: UInt32         = 0xC0392B
        static let codeBackground: UInt32 = 0xECEFEA
    }

    /// 宣纸背景（页面底）：冷调米白，带一丝纸纤维的青灰。
    static let paper = Color(hex: Palette.paper)
    /// 卡片 / 浮层底（比宣纸更白一度，拉开色阶）。
    static let card = Color(hex: Palette.card)
    /// 冷灰分隔线 / 描边。
    static let hairline = Color(hex: 0xE2E6E1)
    /// 松烟墨正文（蓝黑，不是暖棕黑）。
    static let ink = Color(hex: Palette.ink)
    /// 次要文字（青灰）。
    static let inkSecondary = Color(hex: Palette.inkSecondary)
    /// 朱砂（印章红）：全页唯一亮色——主按钮 / 选中态 / 开关 / FAB。
    static let accent = Color(hex: Palette.accent)
    /// 朱砂按压态。
    static let accentPressed = Color(hex: 0x9E2E22)
    /// 代码块 / 行内代码的浅色底（比纸面略深，保持同色系）。
    static let codeBackground = Color(hex: Palette.codeBackground)
    /// 卡片柔和投影（替代描边，hairline 只留给真正的分隔线）。
    static let cardShadow = Color.black.opacity(0.05)

    // MARK: - Hex 字符串（JS / WebView 场景）

    /// 与 Color 同源的 #RRGGBB 字符串：Mermaid 图表等 WKWebView/JS 上下文插值用，
    /// 改 PaperTheme 色板时图表主题自动同步。
    enum Hex {
        static let paper          = PaperTheme.hexString(Palette.paper)
        static let card           = PaperTheme.hexString(Palette.card)
        static let ink            = PaperTheme.hexString(Palette.ink)
        static let inkSecondary   = PaperTheme.hexString(Palette.inkSecondary)
        static let accent         = PaperTheme.hexString(Palette.accent)
        static let codeBackground = PaperTheme.hexString(Palette.codeBackground)
    }

    private static func hexString(_ value: UInt32) -> String {
        String(format: "#%06X", value)
    }

    // MARK: - 圆角

    /// 统一圆角梯度，替换散落的魔法数字。
    enum Radius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let xlarge: CGFloat = 20

        /// 卡片 / 浮层。
        static let card: CGFloat = medium
        /// 按钮。
        static let button: CGFloat = medium
        /// 聊天气泡。
        static let bubble: CGFloat = large
    }

    // MARK: - 间距

    enum Spacing {
        /// 页面边距（20-24 之间的宽松留白）。
        static let page: CGFloat = 22
    }

    // MARK: - 动效

    /// 全 App 统一的动效曲线：全部为 spring（天然可中断），不在各视图散落 easeOut 魔法数字。
    enum Motion {
        /// 标准：视图切换、指示器滑动、卡片出现。
        static let standard = Animation.spring(response: 0.35, dampingFraction: 0.85)
        /// 轻快：按压回弹、消息到达、小元素入场。
        static let quick = Animation.spring(response: 0.25, dampingFraction: 0.9)
        /// 舒缓：空态入场、大面积渐变。
        static let gentle = Animation.spring(response: 0.5, dampingFraction: 0.9)
    }

    // MARK: - 字体

    enum Typography {
        /// 品牌大标题（New York 衬线）。
        static func brandTitle(_ size: CGFloat = 34) -> Font {
            .system(size: size, weight: .bold, design: .serif)
        }
        /// UI 层标题（空态标题等）：系统无衬线——衬线只保留给文档内容与品牌字。
        static func uiTitle3() -> Font {
            .system(.title3, weight: .semibold)
        }
        /// Markdown 预览里的衬线标题（全 App 唯一一套标题字号）。
        static func heading(level: Int) -> Font {
            switch level {
            case 1:  return .system(size: 30, weight: .bold, design: .serif)
            case 2:  return .system(size: 23, weight: .semibold, design: .serif)
            case 3:  return .system(size: 19, weight: .semibold, design: .serif)
            default: return .system(size: 17, weight: .semibold, design: .serif)
            }
        }
        /// 编辑器正文。
        static let editorBody = Font.system(size: 16.5, design: .monospaced)
        /// 代码块。
        static let code = Font.system(size: 14.5, design: .monospaced)
    }
}

// MARK: - Color(hex:)

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

// MARK: - 可复用样式

/// 品牌主按钮：朱砂底白字，按压缩放 + 转深色 + 轻触觉。
struct PaperPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                configuration.isPressed ? PaperTheme.accentPressed : PaperTheme.accent,
                in: RoundedRectangle(cornerRadius: PaperTheme.Radius.button, style: .continuous)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(PaperTheme.Motion.quick, value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .light), trigger: configuration.isPressed) { _, pressed in pressed }
    }
}

extension ButtonStyle where Self == PaperPrimaryButtonStyle {
    static var paperPrimary: PaperPrimaryButtonStyle { PaperPrimaryButtonStyle() }
}

/// 通用按压样式：不改动 label 外观，只加按压缩放 / 透明度 / 回弹 / 轻触觉。
/// 用于 tab、头部按钮、chips、操作行等自绘外观的按钮。
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(PaperTheme.Motion.quick, value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .light), trigger: configuration.isPressed) { _, pressed in pressed }
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
}

/// 圆形图标按钮（发送 / 停止）：强调色底白色细线图标，按压缩放 + 转深色。
struct PaperCircleButtonStyle: ButtonStyle {
    var size: CGFloat = 36

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                configuration.isPressed ? PaperTheme.accentPressed : PaperTheme.accent,
                in: Circle()
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(PaperTheme.Motion.quick, value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .light), trigger: configuration.isPressed) { _, pressed in pressed }
    }
}

// MARK: - 朱砂印章

/// 「墨」字朱砂印：落款签名式的品牌标记（空态等场景）。
/// 方形朱底白字、微斜，像盖在名字旁边的一枚真印。
struct SealStamp: View {
    var size: CGFloat = 26

    var body: some View {
        Text("墨")
            .font(.system(size: size * 0.58, weight: .bold, design: .serif))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                PaperTheme.accent,
                in: RoundedRectangle(cornerRadius: size * 0.19, style: .continuous)
            )
            .rotationEffect(.degrees(3))
            .shadow(color: PaperTheme.accent.opacity(0.3), radius: size * 0.15, y: 1.5)
            .accessibilityHidden(true)
    }
}

// MARK: - UIKit 外观（导航栏 / 标签栏 / 列表分隔线）

enum PaperAppearance {
    /// 应用启动时调用一次：让系统控件也落在纸墨色系里。
    @MainActor
    static func apply() {
        let inkUIColor = UIColor(PaperTheme.ink)

        // 导航栏：纸底、发丝级分隔；标题用系统无衬线（文档文件名的衬线由 DocumentView 自绘标题承担）。
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor(PaperTheme.paper)
        nav.shadowColor = UIColor(PaperTheme.hairline)
        nav.titleTextAttributes = [
            .foregroundColor: inkUIColor,
            .font: UIFont.preferredFont(forTextStyle: .headline),
        ]
        nav.largeTitleTextAttributes = [
            .foregroundColor: inkUIColor,
            .font: UIFont.systemFont(
                ofSize: UIFont.preferredFont(forTextStyle: .largeTitle).pointSize,
                weight: .bold
            ),
        ]
        let navBar = UINavigationBar.appearance()
        navBar.standardAppearance = nav
        navBar.scrollEdgeAppearance = nav
        navBar.compactAppearance = nav

        // 标签栏：卡片底、发丝级顶边、未选中次要色。
        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor(PaperTheme.card)
        tab.shadowColor = UIColor(PaperTheme.hairline)
        let secondary = UIColor(PaperTheme.inkSecondary)
        for item in [tab.stackedLayoutAppearance, tab.inlineLayoutAppearance, tab.compactInlineLayoutAppearance] {
            item.normal.iconColor = secondary
            item.normal.titleTextAttributes = [.foregroundColor: secondary]
        }
        let tabBar = UITabBar.appearance()
        tabBar.standardAppearance = tab
        tabBar.scrollEdgeAppearance = tab

        // 表单分隔线贴近纸色。
        UITableView.appearance().separatorColor = UIColor(PaperTheme.hairline)
    }
}
