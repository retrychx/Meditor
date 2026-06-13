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
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 10.5))
                TextField(L("sidebar.search"), text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.07))
            )
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 4)

            Group {
                if searchText.isEmpty {
                    List {
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
