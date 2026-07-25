import SwiftUI

/// 根视图：以文档为中心的单页结构，不再有底部 tab 导航层级。
/// 底部动作条：左侧胶囊（文档首页 / 新建 / 编辑预览切换 / 设置）+ 右侧 AI 圆钮
/// （sheet 唤起，直接作用于当前文档）。
struct RootView: View {
    @Environment(DocumentStore.self) private var store

    @State private var showingHome = false
    @State private var showingSettings = false
    @State private var showingAI = false

    var body: some View {
        VStack(spacing: 0) {
            DocumentView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            actionBar
        }
        .background(PaperTheme.paper)
        .sheet(isPresented: $showingHome) { DocumentHomeView() }
        .sheet(isPresented: $showingSettings) { SettingsView() }
        .sheet(isPresented: $showingAI) { AIChatView() }
    }

    // MARK: - 底部动作条（Craft 式：左胶囊 + 右 AI 圆钮）

    private var actionBar: some View {
        HStack(spacing: 0) {
            // 胶囊：文档首页 / 新建 / 编辑预览切换 / 设置
            HStack(spacing: 4) {
                barButton(icon: "folder", label: "文档首页") { showingHome = true }
                barButton(icon: "plus", label: "新建文档") { store.createDocument() }
                modeButton
                barButton(icon: "gearshape", label: "设置") { showingSettings = true }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(PaperTheme.card, in: Capsule(style: .continuous))
            .shadow(color: PaperTheme.cardShadow, radius: 18, y: 8)

            Spacer()

            // AI 圆钮：sheet 浮出，直接作用于当前文档
            Button { showingAI = true } label: {
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(PaperTheme.paper)
                    .symbolEffect(.variableColor.iterative, options: .repeating)
                    .frame(width: 48, height: 48)
                    .background(PaperTheme.ink, in: Circle())
                    .shadow(color: PaperTheme.ink.opacity(0.3), radius: 12, y: 5)
                    .contentShape(Circle())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("AI 助手")
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 4)
        // 键盘弹出时动作条保持贴底（被键盘遮住），不被顶上去
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    private func barButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(PaperTheme.inkSecondary)
                .frame(width: 48)
                .padding(.vertical, 8)
                .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(label)
    }

    /// 编辑/预览切换：预览态铅笔（点去编辑）、编辑态文档高亮（点回预览），morph 过渡。
    private var modeButton: some View {
        Button { store.showPreview.toggle() } label: {
            Image(systemName: store.showPreview ? "pencil" : "doc.richtext")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(store.showPreview ? PaperTheme.inkSecondary : PaperTheme.accent)
                .contentTransition(.symbolEffect(.replace.downUp))
                .frame(width: 48)
                .padding(.vertical, 8)
                .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(store.showPreview ? "编辑" : "预览")
    }
}
