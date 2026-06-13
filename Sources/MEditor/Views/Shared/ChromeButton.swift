import SwiftUI

/// A compact icon button for use in chrome bars (tab bar, sidebar header).
/// Lighter than ToolbarIconButton — pure SwiftUI, no NSView wrapping needed.
struct ChromeButton: View {
    let systemName: String
    var help: String = ""
    var isActive: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(isActive ? Color.accentColor : Color.primary.opacity(isHovered ? 0.65 : 0.35))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isActive
                            ? Color.accentColor.opacity(0.1)
                            : isHovered ? Color.black.opacity(0.05) : Color.clear
                        )
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(help)
        .animation(.easeOut(duration: 0.1), value: isHovered)
    }
}

/// Pull-down menu button for the chrome bar.
struct ChromeMenuButton: View {
    let systemName: String
    var help: String = ""
    var isDisabled: Bool = false
    let items: [(title: String, action: () -> Void)]

    @State private var isHovered = false

    var body: some View {
        Menu {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                Button(item.title) { item.action() }
            }
        } label: {
            Image(systemName: systemName)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.secondary.opacity(isHovered ? 1 : 0.7))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isHovered ? Color.primary.opacity(0.07) : Color.clear)
                )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .disabled(isDisabled)
        .onHover { isHovered = $0 }
        .help(help)
        .animation(.easeOut(duration: 0.1), value: isHovered)
    }
}
