import Foundation

// MARK: - Session persistence

extension AppState {

    private var sessionSnapshot: (urls: [URL], selectedIndex: Int?) {
        let urls = tabManager.openTabs.map(\.url)
        let idx  = tabManager.selectedTabID.flatMap { id in
            tabManager.openTabs.firstIndex(where: { $0.id == id })
        }
        return (urls, idx)
    }

    func persistSession() {
        let snap = sessionSnapshot
        sessionStore.scheduleSave(rootURL: rootURL, openTabURLs: snap.urls, selectedIndex: snap.selectedIndex)
    }

    func flushSession() {
        let snap = sessionSnapshot
        sessionStore.saveNow(rootURL: rootURL, openTabURLs: snap.urls, selectedIndex: snap.selectedIndex)
    }

    func restoreSession() {
        guard let session = sessionStore.load() else { return }
        isRestoringSession = true
        defer { isRestoringSession = false }

        if let rootData = session.rootBookmark,
           let resolved = SessionStore.resolveBookmark(rootData),
           fileService.fileExists(at: resolved.url) {
            openFolder(resolved.url)
        }

        var seen = Set(tabManager.openTabs.map(\.url.standardizedFileURL))
        var restored: [(tab: EditorTab, url: URL)] = []
        var restoredSelectedID: UUID?

        for (i, bookmark) in session.tabs.enumerated() {
            guard let resolved = SessionStore.resolveBookmark(bookmark) else { continue }
            let url = resolved.url
            guard fileService.fileExists(at: url), !url.hasDirectoryPath,
                  !seen.contains(url.standardizedFileURL) else { continue }
            if requiresDirectFileAccess(url) { beginAccessing(url) }
            let lang = FileTypeConfiguration.shared.editorLanguage(for: url.pathExtension.lowercased()) ?? .markdown
            let tab  = EditorTab(url: url, content: "", language: lang, awaitingInitialContent: true)
            seen.insert(url.standardizedFileURL)
            if session.selectedTabIndex == i { restoredSelectedID = tab.id }
            restored.append((tab, url))
        }

        tabManager.openTabs.append(contentsOf: restored.map(\.tab))

        if tabManager.selectedTabID == nil,
           let id = restoredSelectedID,
           let tab = tabManager.openTabs.first(where: { $0.id == id }) {
            tabManager.selectedTabID = id
            syncSidebarSelectionToTab(tab)
            syncPreviewContent(from: tab)
        }

        for (tab, url) in restored {
            let tabID = tab.id
            let svc   = fileService
            Task.detached(priority: .userInitiated) { [weak self] in
                do    { let c = try svc.readFile(at: url); await self?.applyLoadedContent(tabID: tabID, content: c) }
                catch { await self?.failLoadingTab(tabID: tabID, url: url, error: error) }
            }
        }
    }
}
