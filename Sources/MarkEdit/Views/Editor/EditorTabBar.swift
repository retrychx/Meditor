import SwiftUI
import UniformTypeIdentifiers

struct EditorTabBar: View {
    @Environment(AppState.self) private var state
    @State private var draggedTabID: UUID?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(state.openTabs) { tab in
                    tabButton(tab)
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
                }
            }
            .padding(.horizontal, 4)
        }
        .frame(height: 32)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func tabButton(_ tab: EditorTab) -> some View {
        let isSelected = tab.id == state.selectedTabID

        return HStack(spacing: 4) {
            Image(systemName: FileTypeConfiguration.shared.icon(for: tab.url.pathExtension))
                .font(.system(size: 10))
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)

            Text(tab.name)
                .font(.system(size: 11, weight: isSelected ? .medium : .regular))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .lineLimit(1)

            if tab.isModified {
                Circle()
                    .fill(.secondary)
                    .frame(width: 6, height: 6)
            }

            Button {
                state.closeTab(tab.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(2)
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.accentColor.opacity(0.1))
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.accentColor.opacity(0.3), lineWidth: 0.5)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            state.selectTab(tab.id)
        }
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
