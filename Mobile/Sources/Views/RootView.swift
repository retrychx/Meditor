import SwiftUI

/// 根视图：文档列表 / 设置 两个一级页面（底部页面胶囊切换），文档页推送进入。
/// 底部栏毛玻璃态：左=页面胶囊，右=＋新建与 AI（均带 hero 展开动画）。
struct RootView: View {
    @Environment(DocumentStore.self) private var store

    private enum Page { case home, settings }

    @State private var page: Page = .home
    @State private var showDocument = false
    @State private var hero = HeroState()
    @Namespace private var heroNS
    @Namespace private var pageIndicator

    var body: some View {
        ZStack {
            NavigationStack {
                ZStack {
                    switch page {
                    case .home:     DocumentHomeView(onOpenDocument: { showDocument = true })
                    case .settings: SettingsView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(page)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(y: 8)),
                    removal: .opacity
                ))
                .animation(PaperTheme.Motion.standard, value: page)
                // 共享底栏悬浮在内容之上（safearea 透底，卡片从胶囊下面穿过）；
                // 只属于一级页面，文档页有自己的悬浮底栏。
                .overlay(alignment: .bottom) {
                    if !showDocument {
                        bottomBar
                            .transition(.opacity.combined(with: .offset(y: 12)))
                    }
                }
                .animation(PaperTheme.Motion.standard, value: showDocument)
                .navigationDestination(isPresented: $showDocument) {
                    DocumentView()
                }
            }
            // 外部来源（微信传入 / Agent 打开）的成功打开自动推进文档页；
            // 文档被删除则退回列表。列表内打开走 onOpenDocument 闭包（同一篇重开也有效）。
            .onChange(of: store.sandboxURL) { _, url in
                showDocument = url != nil
            }
            .onAppear {
                if store.hasDocument {
                    DispatchQueue.main.async { showDocument = true }
                }
            }

            if hero.aiOpen {
                AIHeroOverlay(namespace: heroNS)
                    .zIndex(1)
            }
            if hero.plusZoom {
                PlusZoomOverlay(namespace: heroNS)
                    .zIndex(2)
            }
        }
        .environment(hero)
        .environment(\.heroNamespace, heroNS)
    }

    // MARK: - 底部栏（Craft 式双胶囊：白底玻璃态，safearea 透底）

    /// 胶囊底：与文档页共用同一玻璃质感（GlassCapsuleBackground）。
    private var capsuleBackground: some View {
        GlassCapsuleBackground()
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            // 页面胶囊：文档 / 设置（一级页面，matchedGeometry 滑动）
            HStack(spacing: 4) {
                pageButton(.home, icon: "doc.text", label: "文档")
                pageButton(.settings, icon: "gearshape", label: "设置")
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(capsuleBackground)

            Spacer()

            // 动作胶囊：墨（AI）/ ＋（新建），Craft 同款——图标收进胶囊
            HStack(spacing: 8) {
                BarAIButton(context: "root")
                BarPlusButton(context: "root")
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(capsuleBackground)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 4)
        // 键盘弹出时底栏保持贴底（被键盘遮住），不被顶上去
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    private func pageButton(_ item: Page, icon: String, label: String) -> some View {
        let selected = page == item
        return Button {
            withAnimation(PaperTheme.Motion.standard) { page = item }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .symbolEffect(.bounce, value: selected)
                .foregroundStyle(selected ? PaperTheme.accent : PaperTheme.inkSecondary)
                .frame(width: 52)
                .padding(.vertical, 8)
                .background {
                    if selected {
                        Capsule(style: .continuous)
                            .fill(PaperTheme.accent.opacity(0.12))
                            .matchedGeometryEffect(id: "page-indicator", in: pageIndicator)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(label)
    }
}
