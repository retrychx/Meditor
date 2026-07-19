import SwiftUI

/// 根视图：文档 / AI 助手 / 设置 三个 Tab。
struct RootView: View {
    @Environment(DocumentStore.self) private var store
    @Environment(MobileAISettings.self) private var settings

    var body: some View {
        TabView {
            DocumentView()
                .tabItem { Label("文档", systemImage: "doc.text") }
            AIChatView(store: store, settings: settings)
                .tabItem { Label("AI 助手", systemImage: "bubble.left.and.bubble.right") }
            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
        .tint(PaperTheme.accent)
    }
}
