import SwiftUI

@main
struct MEditorMobileApp: App {
    @State private var store = DocumentStore()
    @State private var settings = MobileAISettings()

    init() {
        PaperAppearance.apply()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(settings)
                .tint(PaperTheme.accent)
                .preferredColorScheme(.light)
                .onOpenURL { url in
                    store.openIncoming(url)
                }
        }
    }
}
