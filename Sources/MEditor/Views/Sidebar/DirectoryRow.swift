import SwiftUI

/// A recursive sidebar tree node — replaces the `AnyView`-based `fileRow`
/// function in FileSidebar.
///
/// Using a View struct instead of a helper function returning `AnyView` gives
/// SwiftUI concrete structural identity: it can diff the tree without heap-
/// allocating a type-erased wrapper for every row on every render pass.
struct SidebarTreeNode: View {
    let item: FileItem
    let searchText: String
    let onAction: (FileAction) -> Void
    let onTap: (FileItem) -> Void

    @Environment(AppState.self) private var state
    @Environment(WorkspaceUIState.self) private var workspaceUI

    private var isExpanded: Bool { workspaceUI.expandedPaths.contains(item.url.path) }

    var body: some View {
        if item.isDirectory {
            DisclosureGroup(
                isExpanded: Binding(
                    get: { isExpanded },
                    set: { workspaceUI.setExpanded(item, $0) }
                )
            ) {
                if item.isLoadingChildren {
                    HStack {
                        ProgressView().controlSize(.small)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                } else if let children = item.children {
                    ForEach(children) { child in
                        SidebarTreeNode(
                            item: child,
                            searchText: searchText,
                            onAction: onAction,
                            onTap: onTap
                        )
                    }
                }
            } label: {
                FileRow(
                    item: item,
                    isSelected: item.id == state.selectedFileID,
                    searchText: searchText,
                    onAction: onAction
                )
                .help(item.url.path)
                .padding(.leading, -6)
            }
            .listRowSeparator(.hidden)
            .onAppear {
                if isExpanded { state.loadChildrenIfNeeded(for: item) }
            }
            .onChange(of: isExpanded) { _, expanded in
                if expanded { state.loadChildrenIfNeeded(for: item) }
            }
        } else {
            FileRow(
                item: item,
                isSelected: item.id == state.selectedFileID,
                searchText: searchText,
                onAction: onAction
            )
            .help(item.url.path)
            .contentShape(Rectangle())
            .onTapGesture { onTap(item) }
            .listRowSeparator(.hidden)
        }
    }
}
