import SwiftUI

struct RightPanelRail: View {
    @Environment(AppState.self) private var state
    @Bindable var workspaceUI: WorkspaceUIState

    private var theme: PreviewTheme { state.themeStore.current }

    var body: some View {
        VStack(spacing: 6) {
            railButton(.insert, icon: "plus", title: L("rightPanel.insert"))

            railButton(.pageInfo, icon: "info.circle", title: L("rightPanel.pageInfo"))
            railButton(.comments, icon: "bubble.left", title: L("rightPanel.comments"))
            railButton(.share, icon: "wifi", title: L("rightPanel.share"))
            railButton(.search, icon: "text.magnifyingglass", title: L("rightPanel.search"))

            Spacer()
        }
        .padding(.top, 8)
        .frame(width: 38)
        .background(theme.chromeBackground.opacity(theme.isDark ? 0.72 : 0.9))
        .overlay(alignment: .leading) {
            theme.separator
                .opacity(theme.isDark ? 0.44 : 0.2)
                .frame(width: 1)
        }
    }

    private func railButton(
        _ panel: WorkspaceUIState.RightPanelKind,
        icon: String,
        title: String
    ) -> some View {
        let isActive = workspaceUI.rightPanel == panel
        return Button {
            withAnimation(DS.Motion.fast) {
                workspaceUI.toggleRightPanel(panel)
            }
        } label: {
            Image(systemName: icon)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(isActive ? Color.accentColor : theme.craftSecondary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isActive ? Color.accentColor.opacity(0.12) : Color.clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(title)
    }
}
