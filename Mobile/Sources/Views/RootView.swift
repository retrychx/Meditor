import SwiftUI

/// 根视图：Craft 式导航模型——文件列表页为根，文档页 / 设置页推送进入。
/// 打开文档（列表点开、微信传入、Agent 打开）统一经 sandboxURL 变化触发推送；
/// AI 是唯一浮层（各页自行以 sheet 唤起）。
struct RootView: View {
    @Environment(DocumentStore.self) private var store

    @State private var showDocument = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            DocumentHomeView(
                onOpenDocument: { showDocument = true },
                onOpenSettings: { showSettings = true }
            )
                .navigationDestination(isPresented: $showDocument) {
                    DocumentView()
                }
                .navigationDestination(isPresented: $showSettings) {
                    SettingsView()
                }
        }
        // 外部来源（微信传入 / Agent 打开）的成功打开自动推进文档页；
        // 文档被删除则退回列表。列表内打开走 onOpenDocument 闭包（同一篇重开也有效）。
        .onChange(of: store.sandboxURL) { _, url in
            showDocument = url != nil
        }
        .onAppear {
            showDocument = store.hasDocument
        }
    }
}
