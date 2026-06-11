import SwiftUI
import UniformTypeIdentifiers

struct EditorTabBar: View {
    @Environment(AppState.self) private var state
    @State private var draggedTabID: UUID?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(state.openTabs) { tab in
                    TabButton(tab: tab, onClose: { state.closeTab(tab.id) })
                        .opacity(draggedTabID == tab.id ? 0.5 : 1)
                        .onDrag {
                            draggedTabID = tab.id
                            return NSItemProvider(object: tab.id.uuidString as NSString)
                        }
                        .onDrop(
                            of: [UTType.text],
                            delegate: TabDropDelegate(
                                tab: tab,
                                draggedTabID: $draggedTabID,
                                state: state
                            )
                        )
                        .contextMenu {
                            Button(L("tab.close")) { state.closeTab(tab.id) }
                            Button(L("tab.closeOthers")) {
                                state.openTabs.filter { $0.id != tab.id }
                                    .forEach { state.closeTab($0.id) }
                            }
                            Button(L("tab.closeAll")) {
                                state.openTabs.forEach { state.closeTab($0.id) }
                            }
                            Divider()
                            Button(L("tab.showInFinder")) {
                                NSWorkspace.shared.activateFileViewerSelecting([tab.url])
                            }
                        }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: state.openTabs.map(\.id))
        }
        .frame(height: 26)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Tab Button

private struct TabButton: View {
    @Environment(AppState.self) private var state
    let tab: EditorTab
    let onClose: () -> Void

    @State private var isHovered = false

    var isSelected: Bool { tab.id == state.selectedTabID }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: FileTypeConfiguration.shared.icon(for: tab.url.pathExtension))
                .font(.system(size: 10))
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)

            Text(tab.name)
                .font(.system(size: 11, weight: isSelected ? .medium : .regular))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            // Close / modified indicator area (fixed width to prevent layout shift)
            ZStack {
                if isHovered {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                } else if tab.isModified {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 5, height: 5)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    // Invisible placeholder to keep width stable
                    Image(systemName: "xmark")
                        .font(.system(size: 8.5, weight: .bold))
                        .hidden()
                }
            }
            .frame(width: 12, height: 12)
            .animation(.easeOut(duration: 0.2), value: tab.isModified)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .frame(minWidth: 80, maxWidth: 160)
        .background(isSelected ? Color(nsColor: .textBackgroundColor) : Color.clear)
        .overlay(alignment: .bottom) {
            if isSelected { Color.accentColor.frame(height: 2) }
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { state.selectTab(tab.id) }
        .help(tab.url.path)
    }
}

// MARK: - Tab Drop Delegate

struct TabDropDelegate: DropDelegate {
    let tab: EditorTab
    @Binding var draggedTabID: UUID?
    let state: AppState

    func performDrop(info: DropInfo) -> Bool {
        draggedTabID = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let draggedID = draggedTabID,
              draggedID != tab.id,
              let sourceIndex = state.openTabs.firstIndex(where: { $0.id == draggedID }),
              let destIndex = state.openTabs.firstIndex(where: { $0.id == tab.id }) else { return }

        state.moveTab(from: sourceIndex, to: destIndex)
        draggedTabID = tab.id
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}
