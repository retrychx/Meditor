import SwiftUI

// MARK: - File Action

enum FileAction: Hashable {
    case newFile(URL)
    case newFolder(URL)
    case rename(FileItem)
    case delete(FileItem)
    case revealInFinder(FileItem)
}

struct FileSidebar: View {
    @Environment(AppState.self) private var state

    @State private var searchText = ""

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
        return flattenMatches(state.fileTree, searchText: searchText)
    }

    /// Walk the tree and collect every leaf file whose name matches the query.
    /// Returns a flat list (no directory hierarchy preserved) — best for search UX
    /// where users want to see all matches regardless of depth.
    private func flattenMatches(_ items: [FileItem], searchText: String) -> [FileItem] {
        var matches: [FileItem] = []
        for item in items {
            if !item.isDirectory && item.name.localizedCaseInsensitiveContains(searchText) {
                matches.append(item)
            }
            if let children = item.children {
                matches.append(contentsOf: flattenMatches(children, searchText: searchText))
            }
        }
        return matches
    }

    var body: some View {
        VStack(spacing: 0) {
            // Compact search
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 10))
                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5))
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(nsColor: .quaternaryLabelColor).opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 4)

            Group {
                if searchText.isEmpty {
                    List(state.fileTree, id: \.id, children: \.children, selection: fileSelectionBinding) { item in
                        FileRow(item: item, isSelected: item.id == state.selectedFileID, onAction: handleFileAction)
                            .help(item.url.path)
                            .listRowSeparator(.hidden)
                    }
                } else if displayedTree.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 20, weight: .light))
                            .foregroundStyle(.tertiary)
                        Text("No matches")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(displayedTree, id: \.id, selection: fileSelectionBinding) { item in
                        FileRow(item: item, isSelected: item.id == state.selectedFileID, onAction: handleFileAction)
                            .help(item.url.path)
                            .listRowSeparator(.hidden)
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .frame(minWidth: 200)
        }
        // MARK: - Create alert
        .alert("New \(createIsFolder ? "Folder" : "File")", isPresented: $showCreateAlert) {
            TextField(createIsFolder ? "Folder name" : "File name", text: $createName)
            Button("Cancel", role: .cancel) {
                resetCreateState()
            }
            Button("Create") {
                createItem()
            }
        } message: {
            Text("Enter a name for the new \(createIsFolder ? "folder" : "file").")
        }
        // MARK: - Rename alert
        .alert("Rename", isPresented: $showRenameAlert) {
            TextField("New name", text: $renameName)
            Button("Cancel", role: .cancel) {
                resetRenameState()
            }
            Button("Rename") {
                renameItem()
            }
        } message: {
            if let target = renameTarget {
                Text("Rename “\(target.name)” to:")
            }
        }
        // MARK: - Delete confirmation
        .confirmationDialog(
            "Are you sure you want to delete “\(itemToDelete?.name ?? "")”?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let item = itemToDelete {
                    deleteItem(item)
                }
                itemToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                itemToDelete = nil
            }
        }
    }

    // MARK: - File Actions

    private func handleFileAction(_ action: FileAction) {
        switch action {
        case .newFile(let parentURL):
            createParentURL = parentURL
            createIsFolder = false
            createName = ""
            showCreateAlert = true

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
        let targetURL = parentURL.appendingPathComponent(fileName)

        do {
            if createIsFolder {
                try FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: false)
            } else {
                try "".write(to: targetURL, atomically: true, encoding: .utf8)
            }
            refresh()
        } catch {
            state.setError("Failed to create \(createIsFolder ? "folder" : "file"): \(error.localizedDescription)")
        }

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

        let newURL = target.url.deletingLastPathComponent().appendingPathComponent(renameName)

        do {
            try FileManager.default.moveItem(at: target.url, to: newURL)
            refresh()
        } catch {
            state.setError("Failed to rename: \(error.localizedDescription)")
        }

        resetRenameState()
    }

    private func resetRenameState() {
        renameName = ""
        renameTarget = nil
    }

    // MARK: - Delete

    private func deleteItem(_ item: FileItem) {
        do {
            try FileManager.default.removeItem(at: item.url)
            refresh()
        } catch {
            state.setError("Failed to delete: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    private func refresh() {
        state.reloadFileTree()
    }

    /// Shared selection binding for file rows.
    /// On selecting a file, opens it; on selecting a directory, just records selection.
    private var fileSelectionBinding: Binding<UUID?> {
        Binding(
            get: { state.selectedFileID },
            set: { newID in
                if let id = newID,
                   let item = state.fileItemMap[id] ?? findItem(by: id, in: state.fileTree),
                   !item.isDirectory {
                    state.openFile(item)
                } else {
                    state.selectedFileID = newID
                }
            }
        )
    }

    private func findItem(by id: UUID, in items: [FileItem]) -> FileItem? {
        for item in items {
            if item.id == id { return item }
            if let children = item.children, let found = findItem(by: id, in: children) {
                return found
            }
        }
        return nil
    }
}
