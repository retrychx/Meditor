import Foundation
import os

// MARK: - Tab management

extension AppState {

    func openFile(_ item: FileItem) {
        guard !item.isDirectory else { return }
        let sid = PerformanceTracer.begin("OpenFile", log: PerformanceTracer.fileOps)

        let needsDirectAccess = requiresDirectFileAccess(item.url)
        if needsDirectAccess {
            beginAccessing(item.url)
        }
        selectedFileID = item.id

        if let existing = openTabs.first(where: { $0.url == item.url }) {
            if needsDirectAccess {
                endAccessing(item.url)
            }
            selectedTabID = existing.id
            syncPreviewContent(from: existing)
            PerformanceTracer.end("OpenFile", log: PerformanceTracer.fileOps, id: sid)
            return
        }

        let lang = FileTypeConfiguration.shared.editorLanguage(for: item.fileExtension) ?? .markdown
        let tab = EditorTab(
            url: item.url,
            content: "",
            language: lang,
            awaitingInitialContent: true
        )
        openTabs.insert(tab, at: 0)
        selectedTabID = tab.id

        if lang == .html {
            showHTMLPreview(fileURL: item.url)
        } else {
            syncPreviewContent(from: tab)
        }

        let tabID = tab.id
        let url = item.url
        let service = fileService

        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let content = try service.readFile(at: url)
                await self?.applyLoadedContent(tabID: tabID, content: content)
            } catch {
                await self?.failLoadingTab(tabID: tabID, url: url, error: error)
            }
            await MainActor.run {
                PerformanceTracer.end("OpenFile", log: PerformanceTracer.fileOps, id: sid)
            }
        }
    }

    func applyLoadedContent(tabID: UUID, content: String) {
        guard let idx = openTabs.firstIndex(where: { $0.id == tabID }) else { return }
        guard openTabs[idx].awaitingInitialContent else { return }
        openTabs[idx].content = content
        openTabs[idx].contentRevision &+= 1
        openTabs[idx].awaitingInitialContent = false
        if selectedTabID == tabID, openTabs[idx].language == .markdown {
            syncPreviewContent(from: openTabs[idx])
        }
    }

    func failLoadingTab(tabID: UUID, url: URL, error: Error) {
        guard let idx = openTabs.firstIndex(where: { $0.id == tabID }) else {
            report(.fileRead(url, underlying: error), logger: AppLog.file)
            return
        }
        guard openTabs[idx].awaitingInitialContent else {
            report(.fileRead(url, underlying: error), logger: AppLog.file)
            return
        }

        let closingURL = openTabs[idx].url
        let wasSelected = (selectedTabID == tabID)
        openTabs.remove(at: idx)
        endAccessing(closingURL)

        if wasSelected {
            if idx < openTabs.count {
                selectedTabID = openTabs[idx].id
            } else if !openTabs.isEmpty {
                selectedTabID = openTabs[openTabs.count - 1].id
            } else {
                selectedTabID = nil
                clearPreview()
            }
            if let tab = selectedTab {
                syncSidebarSelectionToTab(tab)
                syncPreviewContent(from: tab)
            } else {
                selectedFileID = nil
            }
        }

        report(.fileRead(url, underlying: error), logger: AppLog.file)
    }

    func closeTab(_ tabID: UUID) {
        guard let idx = openTabs.firstIndex(where: { $0.id == tabID }) else { return }
        let tab = openTabs[idx]
        if tab.isModified {
            pendingCloseTab = tab
            showingCloseConfirmation = true
            return
        }
        performCloseTab(tabID)
    }

    func confirmCloseTab(save: Bool) {
        guard let tab = pendingCloseTab else { return }
        if save { saveTab(tab) }
        performCloseTab(tab.id)
        pendingCloseTab = nil
        showingCloseConfirmation = false
    }

    func performCloseTab(_ tabID: UUID) {
        guard let idx = openTabs.firstIndex(where: { $0.id == tabID }) else { return }

        let closingURL = openTabs[idx].url
        openTabs.remove(at: idx)
        endAccessing(closingURL)

        recentlyClosedURLs.append(closingURL)
        if recentlyClosedURLs.count > Self.recentlyClosedLimit {
            recentlyClosedURLs.removeFirst()
        }

        if selectedTabID == tabID {
            if idx < openTabs.count {
                selectedTabID = openTabs[idx].id
            } else if !openTabs.isEmpty {
                selectedTabID = openTabs.last?.id
            } else {
                selectedTabID = nil
                clearPreview()
            }
        }

        if let newTab = selectedTab {
            syncSidebarSelectionToTab(newTab)
            syncPreviewContent(from: newTab)
        } else {
            selectedFileID = nil
        }
    }

    func updateTabContent(_ tabID: UUID, content: String) {
        guard let idx = openTabs.firstIndex(where: { $0.id == tabID }) else { return }
        openTabs[idx].content = content
        openTabs[idx].contentRevision &+= 1
        openTabs[idx].isModified = true
        openTabs[idx].awaitingInitialContent = false
        if selectedTabID == tabID {
            syncPreviewContent(from: openTabs[idx])
        }
    }

    func saveTab(_ tab: EditorTab) {
        guard tab.isModified else { return }
        do {
            try fileService.writeFile(at: tab.url, content: tab.content)
            if let idx = openTabs.firstIndex(where: { $0.id == tab.id }) {
                openTabs[idx].isModified = false
                if tab.id == selectedTabID {
                    syncPreviewContent(from: openTabs[idx])
                }
            }
        } catch {
            report(.fileWrite(tab.url, underlying: error), logger: AppLog.file)
        }
    }

    func saveCurrentTab() {
        guard let tab = selectedTab else { return }
        saveTab(tab)
    }

    func selectTab(_ id: UUID) {
        selectedTabID = id
        if let tab = selectedTab {
            syncSidebarSelectionToTab(tab)
            syncPreviewContent(from: tab)
        }
    }

    func syncSidebarSelectionToTab(_ tab: EditorTab) {
        if fileItemMap[tab.url] != nil {
            selectedFileID = tab.url
        }
    }

    func reopenLastClosedTab() {
        while let url = recentlyClosedURLs.popLast() {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            if openTabs.contains(where: { $0.url == url }) { continue }
            openFile(FileItem(url: url, isDirectory: false))
            return
        }
    }

    func selectNextTab() {
        guard openTabs.count > 1, let id = selectedTabID,
              let idx = openTabs.firstIndex(where: { $0.id == id }) else { return }
        let nextIdx = (idx + 1) % openTabs.count
        selectTab(openTabs[nextIdx].id)
    }

    func selectPreviousTab() {
        guard openTabs.count > 1, let id = selectedTabID,
              let idx = openTabs.firstIndex(where: { $0.id == id }) else { return }
        let prevIdx = (idx - 1 + openTabs.count) % openTabs.count
        selectTab(openTabs[prevIdx].id)
    }

    func moveTab(from sourceIndex: Int, to destIndex: Int) {
        guard sourceIndex >= 0, sourceIndex < openTabs.count,
              destIndex >= 0, destIndex < openTabs.count else { return }
        let tab = openTabs.remove(at: sourceIndex)
        openTabs.insert(tab, at: destIndex)
    }
}
