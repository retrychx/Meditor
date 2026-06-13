import SwiftUI
import UniformTypeIdentifiers

// MARK: - Tab Bar

struct EditorTabBar: View {
    @Environment(AppState.self) private var state

    @State private var draggedTabID: UUID?

    private var theme: PreviewTheme { state.themeStore.current }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 1) {
                ForEach(state.openTabs) { tab in
                    TabItem(
                        tab: tab,
                        isSelected: tab.id == state.selectedTabID,
                        editorBg: theme.editorBackground,
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
            .padding(.leading, 4)
            .animation(.easeInOut(duration: 0.18), value: state.openTabs.map(\.id))
        }
        // Tab bar fills the parent chrome bar height — no inner background needed
    }
}

// MARK: - Tab Item

private struct TabItem: View {
    let tab: EditorTab
    let isSelected: Bool
    let editorBg: Color
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 5) {
                // File icon — small, hierarchical
                Image(systemName: FileTypeConfiguration.shared.icon(for: tab.url.pathExtension))
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 10.5))
                    .foregroundStyle(
                        isSelected
                            ? AnyShapeStyle(Color.accentColor)
                            : AnyShapeStyle(Color.secondary.opacity(0.5))
                    )

                // File name
                Text(tab.name)
                    .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(
                        isSelected
                            ? AnyShapeStyle(Color.primary)
                            : AnyShapeStyle(Color.secondary.opacity(0.65))
                    )
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(1)

                // Modified dot / close
                closeOrDot
                    .frame(width: 14, height: 14)
            }
            .padding(.horizontal, 10)
            .frame(minWidth: 80, maxWidth: 160, maxHeight: .infinity)
            .background(tabBackground)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(tab.url.path)
    }

    // MARK: - Background
    // Active: white card with rounded top corners — visually "opens into" the editor.
    // Inactive + hovered: subtle fill.
    // Inactive: fully transparent.

    @ViewBuilder
    private var tabBackground: some View {
        if isSelected {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(editorBg)
                    // Crop bottom corners so the tab flows into the editor seamlessly
                    .padding(.bottom, -6)
                    .clipped()
                // Subtle top border line in accent color — 1px, not 2px
                VStack {
                    Color.accentColor.opacity(0.7).frame(height: 1)
                    Spacer()
                }
            }
            .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
            .animation(.easeOut(duration: 0.15), value: isSelected)
        } else if isHovered {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.primary.opacity(0.06))
                .padding(.horizontal, 2)
                .padding(.vertical, 5)
        }
    }

    @ViewBuilder
    private var closeOrDot: some View {
        ZStack {
            if isHovered || isSelected {
                Button(action: onClose) {
                    ZStack {
                        Circle()
                            .fill(Color.primary.opacity(0.1))
                            .frame(width: 14, height: 14)
                        Image(systemName: "xmark")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(Color.secondary)
                    }
                }
                .buttonStyle(.plain)
                .transition(.scale(scale: 0.7).combined(with: .opacity))
            } else if tab.isModified {
                Circle()
                    .fill(Color.orange.opacity(0.85))
                    .frame(width: 5, height: 5)
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
