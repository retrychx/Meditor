import Foundation

// MARK: - File tree forwarding, CRUD, and cross-domain coordination

extension AppState {

    // MARK: - FileTreeManager forwarding

    var fileTree: [FileItem]           { fileTreeManager.fileTree }
    var fileItemMap: [URL: FileItem]   { fileTreeManager.fileItemMap }
    var indexedFiles: [FileItem]       { fileTreeManager.indexedFiles }

    func reloadFileTree() {
        guard let rootURL else { return }
        fileTreeManager.reload(rootURL: rootURL)
    }

    func loadChildrenIfNeeded(for item: FileItem) { fileTreeManager.loadChildrenIfNeeded(for: item) }
    func isSameOrDescendant(_ url: URL, of base: URL) -> Bool { fileTreeManager.isSameOrDescendant(url, of: base) }
    func replacingDescendantURL(_ url: URL, from old: URL, to new: URL) -> URL? { fileTreeManager.replacingDescendantURL(url, from: old, to: new) }

    // MARK: - Open folder

    func openFolder(_ url: URL) {
        let normalized = url.standardizedFileURL
        let previous   = rootURL?.standardizedFileURL
        if previous != normalized { beginAccessing(normalized) }
        rootURL = url
        if let previous, previous != normalized { endAccessing(previous) }

        tabManager.openTabs.forEach { endAccessing($0.url) }
        tabManager.openTabs.removeAll()
        tabManager.selectedTabID = nil
        selectedFileID = nil
        previewManager.clear()
        // Load the tree BEFORE setting rootURL so that when ContentView switches
        // from welcomeScreen → mainLayout, fileTree is already populated.
        // This eliminates the empty-list flash on first render.
        fileTreeManager.reloadFresh(rootURL: url)
        rootURL = url

        fileWatcher.startWatching(urls: [url]) { [weak self] in
            guard let self else { return }
            self.fileTreeManager.scheduleWatchedReload(rootURL: url)
            self.checkExternalModifications()
        }
    }

    func selectFile(_ item: FileItem) {
        if item.isDirectory { selectedFileID = item.id } else { openFile(item) }
    }

    // MARK: - File CRUD (called by FileSidebar)

    func createFileOrFolder(name: String, isFolder: Bool, parentURL: URL) {
        let target = parentURL.appendingPathComponent(name)
        do {
            if isFolder { try fileService.createDirectory(at: target) }
            else        { try fileService.createFile(at: target, content: "") }
            reloadFileTree()
        } catch { setError(error.localizedDescription) }
    }

    func renameFileItem(from oldURL: URL, newName: String) {
        let newURL = oldURL.deletingLastPathComponent().appendingPathComponent(newName)
        do {
            try fileService.moveItem(from: oldURL, to: newURL)
            handleItemRenamed(from: oldURL, to: newURL)
            reloadFileTree()
        } catch { setError(error.localizedDescription) }
    }

    func deleteFileItem(at url: URL) {
        do {
            try fileService.removeItem(at: url)
            handleItemDeleted(at: url)
            reloadFileTree()
        } catch { setError(error.localizedDescription) }
    }

    // MARK: - Cross-domain coordination

    func syncSidebarSelectionToTab(_ tab: EditorTab) {
        // Always highlight the tab's file in the sidebar, regardless of whether
        // its parent directory has been expanded (fileItemMap may not contain it yet).
        selectedFileID = tab.url
    }

    func handleItemRenamed(from oldURL: URL, to newURL: URL) {
        let old = oldURL.standardizedFileURL, new = newURL.standardizedFileURL
        if let id = selectedFileID,
           let r = fileTreeManager.replacingDescendantURL(id, from: old, to: new) { selectedFileID = r }
        for tab in tabManager.openTabs {
            if let r = fileTreeManager.replacingDescendantURL(tab.url, from: old, to: new) { tab.url = r }
        }
        tabManager.recentlyClosedURLs = tabManager.recentlyClosedURLs.compactMap {
            fileTreeManager.replacingDescendantURL($0, from: old, to: new)
        }
        if let tab = selectedTab { syncPreviewContent(from: tab) }
    }

    func handleItemDeleted(at deletedURL: URL) {
        let deleted = deletedURL.standardizedFileURL
        tabManager.openTabs.filter   { fileTreeManager.isSameOrDescendant($0.url, of: deleted) }
                           .forEach  { endAccessing($0.url) }
        tabManager.openTabs.removeAll         { fileTreeManager.isSameOrDescendant($0.url, of: deleted) }
        tabManager.recentlyClosedURLs.removeAll { fileTreeManager.isSameOrDescendant($0, of: deleted) }

        if let id = selectedFileID,
           fileTreeManager.isSameOrDescendant(id, of: deleted) { selectedFileID = nil }

        if let id = tabManager.selectedTabID,
           !tabManager.openTabs.contains(where: { $0.id == id }) {
            tabManager.selectedTabID = tabManager.openTabs.first?.id
        }

        if let tab = selectedTab { syncSidebarSelectionToTab(tab); syncPreviewContent(from: tab) }
        else                     { tabManager.selectedTabID = nil; previewManager.clear() }
    }
}
