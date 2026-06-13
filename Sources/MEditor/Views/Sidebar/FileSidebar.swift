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

struct FileSidebar: View {
    @Environment(AppState.self) private var state

    @State private var searchText = ""
    /// Persisted set of expanded directory paths (URL.path strings).
    @State private var expandedPaths: Set<String> = {
        let saved = UserDefaults.standard.stringArray(forKey: "sidebar.expandedPaths") ?? []
        return Set(saved)
    }()

    // Create file/folder
    @State private var showCreateAlert = false
    @State private var createName = ""
    @State private var createParentURL: URL?
    @State private var createIsFolder = false

    // Rename
    @State private var showRenameAlert = false
    @State private var renameName = ""
    @State private var renameTarget: FileItem?

    // Delete
    @State private var showDeleteConfirmation = false
    @State private var itemToDelete: FileItem?

    private var displayedTree: [FileItem] {
        guard !searchText.isEmpty else { return state.fileTree }
        if !state.indexedFiles.isEmpty {
            return state.indexedFiles.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        return flattenLoadedMatches(state.fileTree, searchText: searchText)
    }

    private func flattenLoadedMatches(_ items: [FileItem], searchText: String) -> [FileItem] {
        var matches: [FileItem] = []
        for item in items {
            if !item.isDirectory && item.name.localizedCaseInsensitiveContains(searchText) {
                matches.append(item)
            }
            if let children = item.children {
                matches.append(contentsOf: flattenLoadedMatches(children, searchText: searchText))
            }
        }
        return matches
    }

    var body: some View {
        let theme = state.themeStore.current
        return VStack(spacing: 0) {
            // Craft-style search bar — inset, subtle
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(theme.craftSecondary)
                    .font(.system(size: 11))
                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.craftPrimary)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
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
                    .fill(theme.craftHover.opacity(1.5))
            )
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 4)

            Group {
                if searchText.isEmpty {
                    List {
                        // Craft-style section header
                        if let rootURL = state.rootURL {
                            sectionHeader(rootURL.lastPathComponent.uppercased())
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .listRowInsets(.init(top: 8, leading: 8, bottom: 2, trailing: 8))
                        }
                        ForEach(state.fileTree) { item in
                            SidebarTreeNode(
                                item: item,
                                searchText: searchText,
                                expandedPaths: expandedPaths,
                                onExpandedChange: handleExpandedChange,
                                onAction: handleFileAction,
                                onTap: { selectSidebarItem($0) }
                            )
                        }
                    }
                } else if displayedTree.isEmpty {
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
                        FileRow(item: item, isSelected: item.id == state.selectedFileID, searchText: searchText, onAction: handleFileAction)
                            .help(item.url.path)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                state.openFile(item)
                            }
                            .listRowSeparator(.hidden)
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .frame(minWidth: 200)

            // Craft-style: New File button pinned to bottom of sidebar
            if state.rootURL != nil {
                Divider().opacity(0.4)
                HStack(spacing: 6) {
                    Button {
                        createParentURL = state.rootURL
                        createIsFolder = false
                        createName = ""
                        showCreateAlert = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "square.and.pencil")
                                .font(.system(size: 12))
                            Text(L("menu.newFile"))
                                .font(.system(size: 12.5))
                        }
                        .foregroundStyle(theme.craftSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        createParentURL = state.rootURL
                        createIsFolder = true
                        createName = ""
                        showCreateAlert = true
                    } label: {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.craftSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 4)
            }
        }
        // MARK: - Create alert
        .alert(L(createIsFolder ? "menu.newFolder" : "menu.newFile"), isPresented: $showCreateAlert) {
            TextField(L(createIsFolder ? "create.folderName" : "create.fileName"), text: $createName)
            Button(L("common.cancel"), role: .cancel) {
                resetCreateState()
            }
            Button(L("common.create")) {
                createItem()
            }
        } message: {
            Text(L(createIsFolder ? "create.messageFolder" : "create.messageFile"))
        }
        // MARK: - Rename alert
        .alert(L("rename.title"), isPresented: $showRenameAlert) {
            TextField(L("rename.newName"), text: $renameName)
            Button(L("common.cancel"), role: .cancel) {
                resetRenameState()
            }
            Button(L("rename.title")) {
                renameItem()
            }
        } message: {
            if let target = renameTarget {
                Text(L("rename.messageFormat", target.name))
            }
        }
        // MARK: - Delete confirmation
        .confirmationDialog(
            L("delete.confirmFormat", itemToDelete?.name ?? ""),
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(L("common.delete"), role: .destructive) {
                if let item = itemToDelete {
                    deleteItem(item)
                }
                itemToDelete = nil
            }
            Button(L("common.cancel"), role: .cancel) {
                itemToDelete = nil
            }
        }
    }

    // MARK: - File Actions

    private func handleFileAction(_ action: FileAction) {
        switch action {
        case .newFile(let parentURL):
            state.templateCreateParentURL = parentURL  // remember target dir
            createIsFolder = false
            state.showingTemplatePicker = true

        case .newFolder(let parentURL):
            createParentURL = parentURL
            createIsFolder = true
            createName = ""
            showCreateAlert = true

        case .rename(let item):
            renameTarget = item
            renameName = item.name
            showRenameAlert = true

        case .delete(let item):
            itemToDelete = item
            showDeleteConfirmation = true

        case .copyAbsolutePath(let item):
            copyToPasteboard(item.url.path)

        case .copyRelativePath(let item):
            copyToPasteboard(FilePathFormatter.relativePath(for: item.url, rootURL: state.rootURL))

        case .revealInFinder(let item):
            NSWorkspace.shared.activateFileViewerSelecting([item.url])
        }
    }

    // MARK: - Create

    private func createItem() {
        guard let parentURL = createParentURL, !createName.isEmpty else {
            resetCreateState()
            return
        }

        let fileName: String
        if createIsFolder {
            fileName = createName
        } else {
            fileName = createName.hasSuffix(".md") ? createName : "\(createName).md"
        }

        state.createFileOrFolder(name: fileName, isFolder: createIsFolder, parentURL: parentURL)
        resetCreateState()
    }

    private func resetCreateState() {
        createName = ""
        createParentURL = nil
    }

    // MARK: - Rename

    private func renameItem() {
        guard let target = renameTarget, !renameName.isEmpty else {
            resetRenameState()
            return
        }

        state.renameFileItem(from: target.url, newName: renameName)
        resetRenameState()
    }

    private func resetRenameState() {
        renameName = ""
        renameTarget = nil
    }

    // MARK: - Delete

    private func deleteItem(_ item: FileItem) {
        state.deleteFileItem(at: item.url)
    }

    // MARK: - Helpers

    /// Craft-style section header: small caps, muted, no decoration
    private func sectionHeader(_ title: String) -> some View {
        let theme = state.themeStore.current
        return Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(theme.craftSecondary)
            .kerning(0.5)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func refresh() {
        state.reloadFileTree()
    }

    private func copyToPasteboard(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }

    private func selectSidebarItem(_ item: FileItem) {
        state.selectFile(item)
    }

    // MARK: - Expanded paths

    private func handleExpandedChange(_ item: FileItem, _ expanded: Bool) {
        if expanded {
            expandedPaths.insert(item.url.path)
            state.loadChildrenIfNeeded(for: item)
        } else {
            expandedPaths.remove(item.url.path)
        }
        persistExpandedPaths()
    }

    private func persistExpandedPaths() {
        UserDefaults.standard.set(Array(expandedPaths), forKey: "sidebar.expandedPaths")
    }
}
