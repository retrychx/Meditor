import SwiftUI
import UniformTypeIdentifiers

// MARK: - Tab Bar

struct EditorTabBar: View {
    @Environment(AppState.self) private var state

    @State private var draggedTabID: UUID?

    private var theme: PreviewTheme { state.themeStore.current }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Chrome tray
            theme.chromeBackground
                .ignoresSafeArea(edges: .top)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(state.openTabs) { tab in
                        TabItem(
                            tab: tab,
                            isSelected: tab.id == state.selectedTabID,
                            editorBg: theme.editorBackground,
                            chromeBg: theme.chromeBackground,
                            onSelect: { state.selectTab(tab.id) },
                            onClose: { state.closeTab(tab.id) }
                        )
                        .opacity(draggedTabID == tab.id ? 0.4 : 1)
                        .animation(.easeOut(duration: 0.12), value: draggedTabID)
                        .onDrag {
                            draggedTabID = tab.id
                            return NSItemProvider(object: tab.id.uuidString as NSString)
                        }
                        .onDrop(
                            of: [UTType.text],
                            delegate: TabDropDelegate(tab: tab, draggedTabID: $draggedTabID, state: state)
                        )
                        .contextMenu {
                            Button(L("tab.close")) { state.closeTab(tab.id) }
                            Button(L("tab.closeOthers")) {
                                state.openTabs.filter { $0.id != tab.id }.forEach { state.closeTab($0.id) }
                            }
                            Button(L("tab.closeAll")) { state.openTabs.forEach { state.closeTab($0.id) } }
                            Divider()
                            Button(L("tab.showInFinder")) {
                                NSWorkspace.shared.activateFileViewerSelecting([tab.url])
                            }
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.18), value: state.openTabs.map(\.id))
            }
        }
        .frame(height: 30)
    }
}

// MARK: - Tab Item

private struct TabItem: View {
    let tab: EditorTab
    let isSelected: Bool
    let editorBg: Color
    let chromeBg: Color
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 5) {
                // File type icon
                Image(systemName: FileTypeConfiguration.shared.icon(for: tab.url.pathExtension))
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(isSelected ? Color.accentColor.opacity(0.9) : Color.secondary.opacity(0.5))

                // File name
                Text(tab.name)
                    .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary.opacity(0.6))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)

                // Modified dot / close button
                closeOrDot
                    .frame(width: 14, height: 14)
            }
            .padding(.horizontal, 11)
            .frame(minWidth: 80, maxWidth: 150, maxHeight: .infinity)
            // Active tab lifts up to match editor — inactive sits in chrome tray
            .background(isSelected ? editorBg : (isHovered ? editorBg.opacity(0.45) : Color.clear))
            .animation(.easeOut(duration: 0.13), value: isSelected)
            .animation(.easeOut(duration: 0.08), value: isHovered)
            // Active tab: top accent stripe
            .overlay(alignment: .top) {
                if isSelected {
                    Color.accentColor
                        .frame(height: 2)
                        .transition(.opacity)
                        .animation(.easeOut(duration: 0.15), value: isSelected)
                }
            }
            // Thin right separator between tabs
            .overlay(alignment: .trailing) {
                chromeBg.opacity(0.6).frame(width: 1).padding(.vertical, 6)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(tab.url.path)
    }

    @ViewBuilder
    private var closeOrDot: some View {
        ZStack {
            if isHovered || isSelected {
                Button(action: onClose) {
                    ZStack {
                        Circle()
                            .fill(Color.primary.opacity(tab.isModified ? 0.18 : 0.1))
                            .frame(width: 14, height: 14)
                        Image(systemName: "xmark")
                            .font(.system(size: 7.5, weight: .bold))
                            .foregroundStyle(Color.secondary)
                    }
                }
                .buttonStyle(.plain)
                .transition(.scale(scale: 0.7).combined(with: .opacity))
            } else if tab.isModified {
                Circle()
                    .fill(Color.orange.opacity(0.85))
                    .frame(width: 5.5, height: 5.5)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Color.clear
            }
        }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .animation(.easeOut(duration: 0.15), value: tab.isModified)
    }
}

// MARK: - Tab Drop Delegate

struct TabDropDelegate: DropDelegate {
    let tab: EditorTab
    @Binding var draggedTabID: UUID?
    let state: AppState

    func performDrop(info: DropInfo) -> Bool { draggedTabID = nil; return true }

    func dropEntered(info: DropInfo) {
        guard let from = draggedTabID,
              from != tab.id,
              let src = state.openTabs.firstIndex(where: { $0.id == from }),
              let dst = state.openTabs.firstIndex(where: { $0.id == tab.id }) else { return }
        state.moveTab(from: src, to: dst)
        draggedTabID = tab.id
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
}
