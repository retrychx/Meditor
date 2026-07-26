import SwiftUI

/// AI 面板 / 新建文档的 hero 展开状态（RootView 注入 environment）。
@Observable
final class HeroState {
    var aiOpen = false
    var plusZoom = false
    /// 触发源的 matchedGeometry id（根底栏与文档页底栏各有一套按钮，用 id 区分）。
    var aiZoomID = "ai"
    var plusZoomID = "plus"
}

private struct HeroNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    var heroNamespace: Namespace.ID? {
        get { self[HeroNamespaceKey.self] }
        set { self[HeroNamespaceKey.self] = newValue }
    }
}

// MARK: - 底栏共享按钮（＋ 新建 / AI 助手）

/// matchedGeometry 的可选包装：无 namespace 时退化为普通视图。
private struct HeroMatch: ViewModifier {
    let id: String
    let namespace: Namespace.ID?
    let hidden: Bool

    func body(content: Content) -> some View {
        if let namespace {
            content
                .matchedGeometryEffect(id: id, in: namespace)
                .opacity(hidden ? 0 : 1)
        } else {
            content
        }
    }
}

/// ＋ 新建：与左胶囊一致的线图标（plus 墨色），轻量不突兀。
/// 点击 hero 放大成整页纸底再推入新文档。
struct BarPlusButton: View {
    /// 按钮所在栏位的标识（"root" / "doc"），用于区分 matchedGeometry 源。
    let context: String

    @Environment(HeroState.self) private var hero
    @Environment(\.heroNamespace) private var heroNS

    var body: some View {
        Button {
            hero.plusZoomID = "plus-\(context)"
            withAnimation(PaperTheme.Motion.standard) { hero.plusZoom = true }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(PaperTheme.ink)
                .frame(width: 34, height: 34)
                .contentShape(Circle())
                .modifier(HeroMatch(id: "plus-\(context)", namespace: heroNS, hidden: hero.plusZoom))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("新建文档")
    }
}

/// AI 助手：朱砂浅底小圆徽 + 衬线「墨」——保留品牌印记但去实心重感。
struct BarAIButton: View {
    let context: String

    @Environment(HeroState.self) private var hero
    @Environment(\.heroNamespace) private var heroNS

    var body: some View {
        Button {
            hero.aiZoomID = "ai-\(context)"
            withAnimation(PaperTheme.Motion.standard) { hero.aiOpen = true }
        } label: {
            Text("墨")
                .font(.system(size: 14, weight: .bold, design: .serif))
                .foregroundStyle(PaperTheme.seal)
                .frame(width: 34, height: 34)
                .background(PaperTheme.seal.opacity(0.12), in: Circle())
                .contentShape(Circle())
                .modifier(HeroMatch(id: "ai-\(context)", namespace: heroNS, hidden: hero.aiOpen))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("AI 助手")
    }
}

// MARK: - Hero 浮层

/// AI 面板 hero 浮层：圆钮（matchedGeometry 源）飞到全屏圆角面板，下拉/点遮罩飞回。
/// iOS 17 没有 .zoom 转场（iOS 18+），这里用 matchedGeometryEffect 手写。
struct AIHeroOverlay: View {
    let namespace: Namespace.ID

    @Environment(HeroState.self) private var hero
    @State private var contentVisible = false
    @State private var showHistory = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // 遮罩：面板内容就绪前不吃点击——否则点 AI 钮的同一抬手会落在遮罩上
            // 把刚展开的面板立刻关掉（touch down 打开、touch up 误触遮罩）。
            Color.black.opacity(contentVisible ? 0.22 : 0)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { close() }
                .allowsHitTesting(contentVisible)

            VStack(spacing: 0) {
                Spacer(minLength: 44)
                VStack(spacing: 0) {
                    // 顶部抓手区（iOS sheet 风格：只有抓手，不用 X）；
                    // 历史钮收进同一行，与 AIChatView 的标题栏不再叠两层。
                    ZStack {
                        Capsule()
                            .fill(PaperTheme.inkSecondary.opacity(0.3))
                            .frame(width: 36, height: 5)
                        HStack {
                            Spacer()
                            Button { showHistory = true } label: {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(PaperTheme.inkSecondary)
                                    .frame(width: 32, height: 32)
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.pressable)
                            .accessibilityLabel("历史会话")
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 9)
                    .padding(.bottom, 3)
                    .contentShape(Rectangle())
                    .opacity(contentVisible ? 1 : 0)
                    .allowsHitTesting(contentVisible)
                    // 整行可下拉关闭；simultaneousGesture 防 DragGesture 抢历史钮点击
                    .simultaneousGesture(
                        DragGesture().onEnded { value in
                            if value.translation.height > 40 { close() }
                        }
                    )

                    if contentVisible {
                        // 隐藏 AIChatView 自带导航栏，面板头部只有抓手这一层
                        AIChatView()
                            .toolbar(.hidden, for: .navigationBar)
                            .transition(.opacity)
                    }
                }
                .background(PaperTheme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
                // 面板撑满可用高度：包内容高度会在输入区下留出奇怪的灰色空区
                .frame(maxHeight: .infinity, alignment: .top)
                .matchedGeometryEffect(id: hero.aiZoomID, in: namespace)
            }
            .sheet(isPresented: $showHistory) {
                AIHistorySheet()
                    .presentationDetents([.medium, .large])
            }
        }
        .onAppear {
            withAnimation(PaperTheme.Motion.standard.delay(0.18)) { contentVisible = true }
        }
    }

    private func close() {
        withAnimation(PaperTheme.Motion.standard) {
            contentVisible = false
            hero.aiOpen = false
        }
    }
}

/// 新建文档 hero：＋ 圆钮放大成整页纸底，随后创建并推入新文档，纸底淡出。
struct PlusZoomOverlay: View {
    let namespace: Namespace.ID

    @Environment(HeroState.self) private var hero
    @Environment(DocumentStore.self) private var store

    var body: some View {
        PaperTheme.paper
            .ignoresSafeArea()
            .matchedGeometryEffect(id: hero.plusZoomID, in: namespace)
            .task {
                try? await Task.sleep(for: .milliseconds(260))
                guard !Task.isCancelled else { return }
                store.createDocument()
                withAnimation(PaperTheme.Motion.standard) { hero.plusZoom = false }
            }
    }
}
