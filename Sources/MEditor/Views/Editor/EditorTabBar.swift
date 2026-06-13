import SwiftUI
import UniformTypeIdentifiers

struct EditorTabBar: View {
    @Environment(AppState.self) private var state
    @State private var draggedTabID: UUID?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 1) {
                ForEach(state.openTabs) { tab in
                    TabButton(tab: tab, onClose: { state.closeTab(tab.id) })
                        .opacity(draggedTabID == tab.id ? 0.45 : 1)
                        .animation(DS.Motion.fast, value: draggedTabID)
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
            .padding(.horizontal, 4)
            .animation(DS.Motion.standard, value: state.openTabs.map(\.id))
        }
        .frame(height: 34)
        .background(DS.Color.chromeBg)
        .overlay(alignment: .bottom) {
            DS.Color.divider.frame(height: 1)
        }
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
        HStack(spacing: 5) {
            // File type icon
            Image(systemName: FileTypeConfiguration.shared.icon(for: tab.url.pathExtension))
                .font(.system(size: 10.5, weight: .regular))
                .foregroundStyle(
                    isSelected
                        ? AnyShapeStyle(Color.accentColor)
                        : AnyShapeStyle(Color.secondary.opacity(0.7))
                )
                .animation(DS.Motion.fast, value: isSelected)

            // File name
            Text(tab.name)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.primary : Color.secondary.opacity(0.75))
                .lineLimit(1)
                .truncationMode(.middle)
                .animation(DS.Motion.fast, value: isSelected)

            // Close / dot indicator (fixed-width slot)
            ZStack {
                if isHovered || isSelected {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                } else if tab.isModified {
                    Circle()
                        .fill(Color.orange.opacity(0.85))
                        .frame(width: 5.5, height: 5.5)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    // Placeholder — keeps layout stable
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .hidden()
                }
            }
            .frame(width: 14, height: 14)
            .animation(DS.Motion.fast, value: isHovered)
            .animation(DS.Motion.standard, value: tab.isModified)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 0)
        .frame(minWidth: 88, maxWidth: 168, maxHeight: .infinity)
        .background(tabBackground)
        .overlay(alignment: .bottom) { activeUnderline }
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xs, style: .continuous))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { state.selectTab(tab.id) }
        .help(tab.url.path)
    }

    @ViewBuilder
    private var tabBackground: some View {
        RoundedRectangle(cornerRadius: DS.Radius.xs, style: .continuous)
            .fill(
                isSelected
                    ? DS.Color.editorBg
                    : isHovered
                        ? Color.primary.opacity(0.04)
                        : Color.clear
            )
            .animation(DS.Motion.fast, value: isSelected)
            .animation(DS.Motion.micro, value: isHovered)
    }

    @ViewBuilder
    private var activeUnderline: some View {
        if isSelected {
            Color.accentColor
                .frame(height: 2)
                .clipShape(Capsule())
                .padding(.horizontal, 10)
                .transition(.scale.combined(with: .opacity))
                .animation(DS.Motion.springFast, value: isSelected)
        }
    }
}

// MARK: - Tab Drop Delegate

struct TabDropDelegate: DropDelegate {
    let tab: EditorTab
    @Binding var draggedTabID: UUID?
    let state: AppState

    func performDrop(info: DropInfo) -> Bool { draggedTabID = nil; return true }

    func dropEntered(info: DropInfo) {
        guard let draggedID = draggedTabID,
              draggedID != tab.id,
              let src = state.openTabs.firstIndex(where: { $0.id == draggedID }),
              let dst = state.openTabs.firstIndex(where: { $0.id == tab.id }) else { return }
        state.moveTab(from: src, to: dst)
        draggedTabID = tab.id
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
}
