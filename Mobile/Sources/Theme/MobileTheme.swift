import SwiftUI
import UIKit

/// MEditor 移动端「纸墨」设计系统：与产品网页（docs/index.html）同源。
/// 全 App 的颜色 / 字体 / 圆角 / 间距统一从这里取，不在各视图散落字面量。
enum PaperTheme {

    // MARK: - 颜色

    /// 纸面背景（页面底）。
    static let paper = Color(hex: 0xF4F2EC)
    /// 卡片 / 浮层底。
    static let card = Color(hex: 0xFCFBF7)
    /// 深色分隔线 / 描边。
    static let hairline = Color(hex: 0xEAE7DE)
    /// 墨色正文。
    static let ink = Color(hex: 0x201D17)
    /// 次要文字。
    static let inkSecondary = Color(hex: 0x6F6A5C)
    /// 品牌强调色（焦橙）：按钮 / 选中态 / 链接。
    static let accent = Color(hex: 0xB8501F)
    /// 强调色按压态。
    static let accentPressed = Color(hex: 0x9A4418)
    /// 代码块 / 行内代码的浅色底（比纸面略深，保持同色系）。
    static let codeBackground = Color(hex: 0xECE8DC)

    // MARK: - 圆角

    enum Radius {
        static let card: CGFloat = 14
        static let button: CGFloat = 12
        static let bubble: CGFloat = 16
    }

    // MARK: - 间距

    enum Spacing {
        /// 页面边距（20-24 之间的宽松留白）。
        static let page: CGFloat = 22
    }

    // MARK: - 字体

    enum Typography {
        /// 品牌大标题（New York 衬线）。
        static func brandTitle(_ size: CGFloat = 34) -> Font {
            .system(size: size, weight: .bold, design: .serif)
        }
        /// 衬线引导语 / 空态标题。
        static func serifTitle3() -> Font {
            .system(.title3, design: .serif, weight: .semibold)
        }
        /// Markdown 预览里的衬线标题。
        static func heading(level: Int) -> Font {
            let size: CGFloat = switch level {
            case 1: 28
            case 2: 24
            case 3: 20
            default: 17
            }
            return .system(size: size, weight: .semibold, design: .serif)
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

/// 纸墨卡片：浅色底 + 14 圆角 + 0.5pt 描边（比阴影更克制）。
struct PaperCardModifier: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(PaperTheme.card, in: RoundedRectangle(cornerRadius: PaperTheme.Radius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: PaperTheme.Radius.card, style: .continuous)
                    .strokeBorder(PaperTheme.hairline, lineWidth: 0.5)
            }
    }
}

extension View {
    func paperCard(padding: CGFloat = 16) -> some View {
        modifier(PaperCardModifier(padding: padding))
    }
}

/// 品牌主按钮：焦橙底白字，按压转深色。
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
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PaperPrimaryButtonStyle {
    static var paperPrimary: PaperPrimaryButtonStyle { PaperPrimaryButtonStyle() }
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
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - UIKit 外观（导航栏 / 标签栏 / 列表分隔线）

enum PaperAppearance {
    /// 应用启动时调用一次：让系统控件也落在纸墨色系里。
    @MainActor
    static func apply() {
        let inkUIColor = UIColor(PaperTheme.ink)

        // 导航栏：纸底、发丝级分隔、衬线标题。
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor(PaperTheme.paper)
        nav.shadowColor = UIColor(PaperTheme.hairline)
        nav.titleTextAttributes = [
            .foregroundColor: inkUIColor,
            .font: serifUIFont(textStyle: .headline),
        ]
        nav.largeTitleTextAttributes = [
            .foregroundColor: inkUIColor,
            .font: serifUIFont(textStyle: .largeTitle, weight: .bold),
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

    /// New York 衬线 UIFont（失败时退回系统字体）。
    private static func serifUIFont(textStyle: UIFont.TextStyle, weight: UIFont.Weight = .semibold) -> UIFont {
        let base = UIFontDescriptor.preferredFontDescriptor(withTextStyle: textStyle)
        if let serif = base.withDesign(.serif) {
            let traits = serif.addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight]])
            return UIFont(descriptor: traits, size: 0)
        }
        return UIFont.systemFont(ofSize: UIFont.preferredFont(forTextStyle: textStyle).pointSize, weight: weight)
    }
}
