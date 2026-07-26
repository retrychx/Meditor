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

/// ＋ 新建：墨底白加号（Craft 同款），点击 hero 放大成整页纸底再推入新文档。
/// 收在右侧动作胶囊里：小圆钮、不带自己的投影（由胶囊承载）。
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
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(PaperTheme.paper)
                .frame(width: 34, height: 34)
                .background(PaperTheme.ink, in: Circle())
                .contentShape(Circle())
                .modifier(HeroMatch(id: "plus-\(context)", namespace: heroNS, hidden: hero.plusZoom))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("新建文档")
    }
}

/// AI 助手：朱砂圆 + 衬线「墨」（品牌印记），点击 hero 展开 AI 面板。
struct BarAIButton: View {
    let context: String

    @Environment(HeroState.self) private var hero
    @Environment(\.heroNamespace) private var heroNS

    var body: some View {
        Button {
            hero.aiZoomID = "ai-\(context)"
            withAnimation(PaperTheme.Motion.standard) { hero.aiOpen = true }
        } label: {
            SealCircle(size: 34)
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
                    // 顶部把手行（SwiftUI 层）：面板里的 UIKit 导航栏会盖住叠层按钮、
                    // 列表又抢占下拉手势——关闭出口必须在这行。
                    HStack {
                        Button(action: close) {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(PaperTheme.inkSecondary)
                                .frame(width: 30, height: 30)
                                .background(PaperTheme.hairline.opacity(0.6), in: Circle())
                        }
                        .buttonStyle(.pressable)
                        .accessibilityLabel("关闭")
                        Spacer()
                        Capsule()
                            .fill(PaperTheme.inkSecondary.opacity(0.3))
                            .frame(width: 36, height: 5)
                        Spacer()
                        // 与左侧 X 对称的占位，让把手居中
                        Color.clear.frame(width: 30, height: 30)
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                    .padding(.bottom, 2)
                    .contentShape(Rectangle())
                    .opacity(contentVisible ? 1 : 0)
                    .allowsHitTesting(contentVisible)
                    // simultaneousGesture：普通 .gesture 的 DragGesture 按下即识别，
                    // 会抢走行内 X 按钮的点击
                    .simultaneousGesture(
                        DragGesture().onEnded { value in
                            if value.translation.height > 40 { close() }
                        }
                    )

                    if contentVisible {
                        AIChatView()
                            .transition(.opacity)
                    }
                }
                .background(PaperTheme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
                .matchedGeometryEffect(id: hero.aiZoomID, in: namespace)
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
