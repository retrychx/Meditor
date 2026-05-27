import Foundation

// MARK: - Session persistence

extension AppState {

    var sessionSnapshot: (urls: [URL], selectedIndex: Int?) {
        let urls = openTabs.map { $0.url }
        let selectedIdx: Int? = {
            guard let id = selectedTabID else { return nil }
            return openTabs.firstIndex(where: { $0.id == id })
        }()
        return (urls, selectedIdx)
    }

    func persistSession() {
        let snapshot = sessionSnapshot
        sessionStore.scheduleSave(
            rootURL: rootURL,
            openTabURLs: snapshot.urls,
            selectedIndex: snapshot.selectedIndex
        )
    }

    func flushSession() {
        let snapshot = sessionSnapshot
        sessionStore.saveNow(
            rootURL: rootURL,
            openTabURLs: snapshot.urls,
            selectedIndex: snapshot.selectedIndex
        )
    }

    func restoreSession() {
        guard let session = sessionStore.load() else { return }
        isRestoringSession = true
        defer { isRestoringSession = false }

        if let rootData = session.rootBookmark,
           let resolved = SessionStore.resolveBookmark(rootData),
           FileManager.default.fileExists(atPath: resolved.url.path) {
            beginAccessing(resolved.url)
            openFolder(resolved.url)
        }

        let alreadyOpenURLs = Set(openTabs.map { $0.url })
        var restoredTabs: [(EditorTab, URL)] = []
        for tabBookmark in session.tabs {
            guard let resolved = SessionStore.resolveBookmark(tabBookmark) else { continue }
            let url = resolved.url
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            guard !url.hasDirectoryPath else { continue }
            if alreadyOpenURLs.contains(url) { continue }

            beginAccessing(url)
            let lang = FileTypeConfiguration.shared
                .editorLanguage(for: url.pathExtension.lowercased()) ?? .markdown
            let tab = EditorTab(url: url, content: "", language: lang)
            restoredTabs.append((tab, url))
        }
        openTabs.append(contentsOf: restoredTabs.map { $0.0 })

        if selectedTabID == nil,
           let idx = session.selectedTabIndex,
           idx >= 0, idx < restoredTabs.count {
            let restoredTab = restoredTabs[idx].0
            selectedTabID = restoredTab.id
            syncSidebarSelectionToTab(restoredTab)
            syncPreviewContent(from: restoredTab)
        }

        for (tab, url) in restoredTabs {
            let tabID = tab.id
            let service = fileService
            Task.detached(priority: .userInitiated) { [weak self] in
                do {
                    let content = try service.readFile(at: url)
                    await self?.applyLoadedContent(tabID: tabID, content: content)
                } catch {
                    await self?.failLoadingTab(tabID: tabID, url: url, error: error)
                }
            }
        }
    }
}
