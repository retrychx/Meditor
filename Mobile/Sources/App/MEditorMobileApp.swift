import SwiftUI

@main
struct MEditorMobileApp: App {
    @State private var store: DocumentStore
    @State private var settings: MobileAISettings
    /// 全局唯一的 AI 会话：Tab 与文档页悬浮入口共用同一段对话。
    @State private var chat: ChatModel

    init() {
        PaperAppearance.apply()
        let store = DocumentStore()
        let settings = MobileAISettings()
        _store = State(initialValue: store)
        _settings = State(initialValue: settings)
        _chat = State(initialValue: ChatModel(store: store, settings: settings))
        // 冷启动即预热 Mermaid 引擎（恢复的文档含图表才拉起）：
        // JS 解析与首帧渲染并行，图表出图不再等预览出现才开始初始化。
        if store.text.contains("```mermaid") {
            MermaidRenderer.shared.prewarm()
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(settings)
                .environment(chat)
                .tint(PaperTheme.accent)
                .preferredColorScheme(.light)
                .onOpenURL { url in
                    store.openIncoming(url)
                }
        }
    }
}
