import SwiftUI
import UniformTypeIdentifiers

// MARK: - Tab Bar

struct EditorTabBar: View {
    @Environment(AppState.self) private var state
    @State private var draggedTabID: UUID?

    private var theme: PreviewTheme { state.themeStore.current }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(state.openTabs) { tab in
                    TabItem(
                        tab: tab,
                        isSelected: tab.id == state.selectedTabID,
                        isDark: theme.isDark,
                        onSelect: { state.selectTab(tab.id) },
                        onClose: { state.closeTab(tab.id) }
                    )
                    .opacity(draggedTabID == tab.id ? 0.45 : 1)
                    .animation(DS.Motion.fast, value: draggedTabID)
                    .onDrag {
                        draggedTabID = tab.id
                        return NSItemProvider(object: tab.id.uuidString as NSString)
                    }
                    .onDrop(of: [UTType.text],
                            delegate: TabDropDelegate(tab: tab, draggedTabID: $draggedTabID, state: state))
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
            .padding(.horizontal, 6)
            .animation(.easeInOut(duration: 0.18), value: state.openTabs.map(\.id))
        }
    }
}

// MARK: - Tab Item

private struct TabItem: View {
    let tab: EditorTab
    let isSelected: Bool
    let isDark: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 5) {
                // File icon
                Image(systemName: FileTypeConfiguration.shared.icon(for: tab.url.pathExtension))
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 11))
                    .foregroundStyle(
                        isSelected ? AnyShapeStyle(Color.appAccent) : AnyShapeStyle(Color.secondary.opacity(0.5))
                    )

                // File name
                Text(tab.name)
                    .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(
                        isSelected ? AnyShapeStyle(Color.primary) : AnyShapeStyle(Color.secondary.opacity(0.7))
                    )
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(1)

                // Dot or close button
                closeOrDot
                    .frame(width: 14, height: 14)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(minWidth: 72, maxWidth: 180, maxHeight: .infinity)
            .background(tabBackground)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(tab.url.path)
    }

    @ViewBuilder
    private var tabBackground: some View {
        if isSelected {
            // Craft: white (light) or dark-card (dark) rounded pill, subtle shadow
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isDark ? Color(white: 0.22) : Color.white)
                .shadow(color: .black.opacity(isDark ? 0.3 : 0.1), radius: 4, x: 0, y: 1)
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
        } else if isHovered {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.06))
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
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
            }
        }
        .animation(DS.Motion.fast, value: isHovered)
        .animation(DS.Motion.fast, value: tab.isModified)
    }
}

// MARK: - Drop Delegate

struct TabDropDelegate: DropDelegate {
    let tab: EditorTab
    @Binding var draggedTabID: UUID?
    let state: AppState

    func performDrop(info: DropInfo) -> Bool { draggedTabID = nil; return true }

    func dropEntered(info: DropInfo) {
        guard let from = draggedTabID, from != tab.id,
              let src = state.openTabs.firstIndex(where: { $0.id == from }),
              let dst = state.openTabs.firstIndex(where: { $0.id == tab.id }) else { return }
        state.moveTab(from: src, to: dst)
        draggedTabID = tab.id
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
}
