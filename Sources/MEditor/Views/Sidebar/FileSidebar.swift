import SwiftUI

// MARK: - File Action

enum FileAction: Hashable {
    case newFile(URL)
    case newFolder(URL)
    case rename(FileItem)
    case delete(FileItem)
    case copyAbsolutePath(FileItem)
    case copyRelativePath(FileItem)
    case revealInFinder(FileItem)
}

// MARK: - FileSidebar (Craft-style)

struct FileSidebar: View {
    @Environment(AppState.self) private var state
    @Environment(WorkspaceUIState.self) private var workspaceUI

    @State private var searchText = ""
    @State private var expandedPaths: Set<String> = {
        Set(UserDefaults.standard.stringArray(forKey: "sidebar.expandedPaths") ?? [])
    }()

    @State private var showCreateAlert = false
    @State private var createName = ""
    @State private var createParentURL: URL?
    @State private var createIsFolder = false

    @State private var showRenameAlert = false
    @State private var renameName = ""
    @State private var renameTarget: FileItem?

    @State private var showDeleteConfirmation = false
    @State private var itemToDelete: FileItem?

    private var displayedTree: [FileItem] {
        guard !searchText.isEmpty else { return state.fileTree }
        if !state.indexedFiles.isEmpty {
            return state.indexedFiles.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        return flattenLoadedMatches(state.fileTree)
    }

    private func flattenLoadedMatches(_ items: [FileItem]) -> [FileItem] {
        var result: [FileItem] = []
        for item in items {
            if !item.isDirectory && item.name.localizedCaseInsensitiveContains(searchText) { result.append(item) }
            if let children = item.children { result.append(contentsOf: flattenLoadedMatches(children)) }
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Space Switcher (Craft top row) ──
            SpaceSwitcherRow()

            // ── Search bar ──
            SidebarSearchBar(text: $searchText)
                .padding(.horizontal, 8)
                .padding(.top, 6)
                .padding(.bottom, 8)

            // ── Content ──
            if searchText.isEmpty {
                mainContent
            } else {
                searchResultsView
            }

            // ── Pinned app views (Tasks / Calendar) ──
            // These are app-level views, not files, so they live pinned at the
            // bottom — visually separated from the file tree above.
            if searchText.isEmpty {
                PinnedViewsBar()
            }

            // ── Bottom toolbar ──
            SidebarBottomBar(
                onNewFile: {
                    state.templateCreateParentURL = state.rootURL
                    createIsFolder = false
                    state.showingTemplatePicker = true
                },
                onNewFolder: {
                    createParentURL = state.rootURL; createIsFolder = true
                    createName = ""; showCreateAlert = true
                }
            )
        }
        .background(.clear)
        .sheet(isPresented: $showCreateAlert) {
            InputDialog(
                title: L(createIsFolder ? "menu.newFolder" : "menu.newFile"),
                message: L(createIsFolder ? "create.messageFolder" : "create.messageFile"),
                placeholder: L(createIsFolder ? "create.folderName" : "create.fileName"),
                confirmTitle: L("common.create"),
                text: $createName,
                onConfirm: { createItem(); showCreateAlert = false },
                onCancel: { resetCreateState(); showCreateAlert = false }
            )
        }
        .sheet(isPresented: $showRenameAlert) {
            InputDialog(
                title: L("rename.title"),
                message: renameTarget.map { L("rename.messageFormat", $0.name) } ?? "",
                placeholder: L("rename.newName"),
                confirmTitle: L("rename.title"),
                text: $renameName,
                onConfirm: { renameItem(); showRenameAlert = false },
                onCancel: { resetRenameState(); showRenameAlert = false }
            )
        }
        .confirmationDialog(
            L("delete.confirmFormat", itemToDelete?.name ?? ""),
            isPresented: $showDeleteConfirmation, titleVisibility: .visible
        ) {
            Button(L("common.delete"), role: .destructive) {
                if let item = itemToDelete { deleteItem(item) }
                itemToDelete = nil
            }
            Button(L("common.cancel"), role: .cancel) { itemToDelete = nil }
        }
    }

    // MARK: - Main content (when not searching)

    private var mainContent: some View {
        List {
            // Folders section
            if !state.fileTree.isEmpty {
                Section {
                    ForEach(state.fileTree) { item in
                        SidebarTreeNode(
                            item: item,
                            searchText: "",
                            expandedPaths: expandedPaths,
                            onExpandedChange: handleExpandedChange,
                            onAction: handleFileAction,
                            onTap: { selectSidebarItem($0) }
                        )
                    }
                } header: {
                    CraftSectionHeader(title: L("sidebar.folders"))
                }
                .listRowInsets(.init(top: 1, leading: 12, bottom: 1, trailing: 12))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var searchResultsView: some View {
        if displayedTree.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(.tertiary)
                Text(L("common.noMatches"))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(displayedTree, id: \.id) { item in
                FileRow(item: item, isSelected: item.id == state.selectedFileID,
                        searchText: searchText, onAction: handleFileAction)
                    .help(item.url.path)
                    .contentShape(Rectangle())
                    .onTapGesture { state.openFile(item) }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
    }

    // MARK: - Actions

    private func handleFileAction(_ action: FileAction) {
        switch action {
        case .newFile(let parentURL):
            state.templateCreateParentURL = parentURL
            createIsFolder = false
            state.showingTemplatePicker = true
        case .newFolder(let parentURL):
            createParentURL = parentURL; createIsFolder = true; createName = ""; showCreateAlert = true
        case .rename(let item):
            renameTarget = item; renameName = item.name; showRenameAlert = true
        case .delete(let item):
            itemToDelete = item; showDeleteConfirmation = true
        case .copyAbsolutePath(let item):
            copyToPasteboard(item.url.path)
        case .copyRelativePath(let item):
            copyToPasteboard(FilePathFormatter.relativePath(for: item.url, rootURL: state.rootURL))
        case .revealInFinder(let item):
            NSWorkspace.shared.activateFileViewerSelecting([item.url])
        }
    }

    private func createItem() {
        guard let parentURL = createParentURL, !createName.isEmpty else { resetCreateState(); return }
        let fileName = createIsFolder ? createName : (createName.hasSuffix(".md") ? createName : "\(createName).md")
        state.createFileOrFolder(name: fileName, isFolder: createIsFolder, parentURL: parentURL)
        resetCreateState()
    }

    private func resetCreateState() { createName = ""; createParentURL = nil }

    private func renameItem() {
        guard let target = renameTarget, !renameName.isEmpty else { resetRenameState(); return }
        state.renameFileItem(from: target.url, newName: renameName)
        resetRenameState()
    }

    private func resetRenameState() { renameName = ""; renameTarget = nil }
    private func deleteItem(_ item: FileItem) { state.deleteFileItem(at: item.url) }

    private func copyToPasteboard(_ value: String) {
        let pb = NSPasteboard.general; pb.clearContents(); pb.setString(value, forType: .string)
    }

    private func selectSidebarItem(_ item: FileItem) { state.selectFile(item) }

    private func handleExpandedChange(_ item: FileItem, _ expanded: Bool) {
        if expanded { expandedPaths.insert(item.url.path); state.loadChildrenIfNeeded(for: item) }
        else { expandedPaths.remove(item.url.path) }
        UserDefaults.standard.set(Array(expandedPaths), forKey: "sidebar.expandedPaths")
    }
}

// MARK: - Space Switcher

private struct SidebarTitlebarRow: View {
    @Bindable var workspaceUI: WorkspaceUIState
    @Environment(AppState.self) private var state
    @State private var isHovered = false

    var body: some View {
        let theme = state.themeStore.current
        HStack(spacing: 0) {
            // macOS traffic lights occupy this area. We keep it empty so the
            // real window controls visually belong to the sidebar, like Craft.
            Color.clear.frame(width: 78)

            Spacer()

            Button {
                withAnimation(DS.Motion.springFast) {
                    workspaceUI.showsSidebar = false
                }
            } label: {
                Image(systemName: "sidebar.left")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.craftSecondary.opacity(isHovered ? 0.9 : 0.58))
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(isHovered ? theme.craftHover : Color.clear)
                    )
            }
            .buttonStyle(.plain)
            .keyboardShortcut("b", modifiers: [.command, .option])
            .help(L("tooltip.hideSidebar"))
            .onHover { isHovered = $0 }
        }
        .frame(height: 36)
        .padding(.trailing, 8)
    }
}

private struct SpaceSwitcherRow: View {
    @Environment(AppState.self) private var state
    @Environment(WorkspaceUIState.self) private var workspaceUI
    @Environment(\.sidebarToggleNS) private var sidebarNS
    @State private var isHovered = false
    @State private var isCollapseHovered = false

    var body: some View {
        let theme = state.themeStore.current
        HStack(spacing: 9) {
            // Workspace icon badge
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.orange.opacity(0.18))
                    .frame(width: 26, height: 26)
                Image(systemName: "folder.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.orange)
            }

            Text(state.rootURL?.lastPathComponent ?? "MEditor")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.craftPrimary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            // Collapse button — lives inside the sidebar card while expanded.
            Button {
                withAnimation(DS.Motion.panel) { workspaceUI.showsSidebar = false }
            } label: {
                Image(systemName: "sidebar.left")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.craftSecondary.opacity(isCollapseHovered ? 0.95 : 0.55))
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isCollapseHovered ? theme.craftHover : Color.clear)
                    )
            }
            .buttonStyle(.plain)
            .onHover { isCollapseHovered = $0 }
            .help(L("tooltip.hideSidebar"))
            .heroMatch("sidebarToggle", in: sidebarNS)
            .animation(DS.Motion.micro, value: isCollapseHovered)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovered ? Color.primary.opacity(0.05) : Color.clear)
                .padding(.horizontal, 4)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .animation(DS.Motion.micro, value: isHovered)
    }
}

// MARK: - Search Bar

private struct SidebarSearchBar: View {
    @Binding var text: String
    @Environment(AppState.self) private var state

    var body: some View {
        let theme = state.themeStore.current
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(theme.craftSecondary)
                .font(.system(size: 11))
            TextField(L("common.search"), text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .foregroundStyle(theme.craftPrimary)
            if !text.isEmpty {
                Button { withAnimation(DS.Motion.micro) { text = "" } } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(theme.craftSecondary)
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme.craftHover)
        )
    }
}

// MARK: - Top Nav Entry (All Docs / Recent / Favorites)

private struct TopNavEntry: View {
    let icon: String
    let label: String
    var isSelected = false
    @Environment(AppState.self) private var state
    @State private var isHovered = false

    var body: some View {
        let theme = state.themeStore.current
        HStack(spacing: 8) {
            Image(systemName: icon)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 14))
                .foregroundStyle(isSelected ? theme.craftPrimary : theme.craftSecondary)
                .frame(width: 20, alignment: .center)
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(isSelected ? theme.craftPrimary : theme.craftPrimary.opacity(0.72))
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.primary.opacity(0.10) : isHovered ? Color.primary.opacity(0.05) : Color.clear)
                .padding(.horizontal, 4)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .animation(DS.Motion.micro, value: isHovered)
    }
}

private struct CraftSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .kerning(0.2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 6)
            .padding(.top, 5)
            .padding(.bottom, 1)
    }
}

private struct PinnedViewsBar: View {
    var body: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.3)
            VStack(spacing: 1) {
                TopNavEntry(icon: "checkmark.circle", label: L("sidebar.tasks"))
                TopNavEntry(icon: "calendar", label: L("sidebar.calendar"))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
    }
}

private struct SidebarBottomBar: View {
    @Environment(AppState.self) private var state
    let onNewFile: () -> Void
    let onNewFolder: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.3)
            HStack {
                SidebarIconButton(icon: "doc.badge.plus", help: L("sidebar.newDocument"), action: onNewFile)
                    .disabled(state.rootURL == nil)
                Spacer()
                SidebarIconButton(icon: "folder.badge.plus", help: L("sidebar.newFolder"), action: onNewFolder)
                    .disabled(state.rootURL == nil)
                SidebarIconButton(icon: "gearshape", help: L("menu.preferences")) {
                    state.showingSettings = true
                }
                .anchorPreference(key: SettingsAnchorKey.self, value: .bounds) { $0 }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.clear)
        }
    }
}

private struct SidebarIconButton: View {
    let icon: String
    let help: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 14))
                .foregroundStyle(Color.secondary.opacity(isHovered ? 1 : 0.55))
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isHovered ? Color.primary.opacity(0.07) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(help)
        .animation(DS.Motion.micro, value: isHovered)
    }
}
