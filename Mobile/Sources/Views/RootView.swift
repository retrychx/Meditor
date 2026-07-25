import SwiftUI

/// 根视图：文档 / AI 助手 / 设置 三个 Tab。
/// 自绘底栏：激活胶囊用 matchedGeometryEffect 在 tab 间滑动，图标选中弹跳。
/// 页面只渲染当前 Tab（三个页面各自的 NavigationStack 常驻会互相盖住导航栏命中）。
struct RootView: View {
    @State private var tab: Tab = .document
    @Namespace private var tabIndicator

    private enum Tab: CaseIterable {
        case document, assistant, settings

        var title: String {
            switch self {
            case .document:  return "文档"
            case .assistant: return "AI 助手"
            case .settings:  return "设置"
            }
        }

        var icon: String {
            switch self {
            case .document:  return "doc.text"
            case .assistant: return "bubble.left.and.bubble.right"
            case .settings:  return "gearshape"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                switch tab {
                case .document:  DocumentView()
                case .assistant: AIChatView()
                case .settings:  SettingsView()
                }
            }
            // 只渲染当前页：三个页面各自带 NavigationStack 时，若常驻视图树仅靠
            // 透明度隐藏，隐藏页的 UINavigationBar（UIKit 层）仍会盖住底部页面
            // 吃掉导航栏按钮的点击——工具栏按钮因此全部失灵（本组件此前的回归）。
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .id(tab)
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .offset(y: 10)),
                removal: .opacity
            ))
            .animation(PaperTheme.Motion.standard, value: tab)
            tabBar
        }
        .background(PaperTheme.paper)
    }

    // MARK: - 底栏（Craft 式悬浮胶囊）

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases, id: \.self) { item in
                tabButton(item)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(PaperTheme.card, in: Capsule(style: .continuous))
        .shadow(color: PaperTheme.cardShadow, radius: 18, y: 8)
        .padding(.horizontal, 32)
        .padding(.bottom, 4)
        // 键盘弹出时底栏保持贴底（被键盘遮住），不被顶上去
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    private func tabButton(_ item: Tab) -> some View {
        let selected = tab == item
        return Button {
            withAnimation(PaperTheme.Motion.standard) { tab = item }
        } label: {
            Image(systemName: item.icon)
                .font(.system(size: 19, weight: .medium))
                .symbolEffect(.bounce, value: selected)
                .foregroundStyle(selected ? PaperTheme.accent : PaperTheme.inkSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background {
                    if selected {
                        Capsule(style: .continuous)
                            .fill(PaperTheme.accent.opacity(0.12))
                            .padding(.horizontal, 12)
                            .matchedGeometryEffect(id: "tab-indicator", in: tabIndicator)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(item.title)
    }
}
