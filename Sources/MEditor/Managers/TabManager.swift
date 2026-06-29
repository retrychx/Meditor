import Foundation
import Observation
import OSLog

/// Owns all tab state and lifecycle operations.
///
/// Cross-cutting concerns (preview sync, sidebar selection, security-scope access)
/// are injected as closures so TabManager has zero dependency on AppState itself.
/// AppState wires these up in its init and forwards its public properties/methods
/// to TabManager so the View layer is unchanged.
@MainActor
@Observable
final class TabManager {

    // MARK: - State

    var openTabs: [EditorTab] = [] {
        didSet { onOpenTabsChanged?() }
    }

    var selectedTabID: UUID? {
        didSet { onSelectedTabIDChanged?() }
    }

    var pendingCloseTab: EditorTab?
    var showingCloseConfirmation = false
    var pendingLargeFile: FileItem?
    var showingLargeFileWarning = false

    @ObservationIgnored var recentlyClosedURLs: [URL] = []
    static let recentlyClosedLimit = 16
    static let largeFileThreshold: Int64 = 1024 * 1024

    // MARK: - Pure dependencies

    let fileService: FileServiceProtocol

    // MARK: - Cross-cutting callbacks (wired by AppState.init)

    /// Called whenever `openTabs` changes (e.g. tab added/removed).
    var onOpenTabsChanged: (() -> Void)?
    /// Called whenever `selectedTabID` changes.
    var onSelectedTabIDChanged: (() -> Void)?
    /// Called after a content mutation that doesn't change `openTabs` itself.
    var onScheduleSessionPersist: (() -> Void)?

    /// Tell the preview manager to sync content from this tab.
    var onSyncPreview: ((EditorTab) -> Void)?
    /// A tab's content was just written to disk (manual save / auto-save).
    /// Used to refresh disk-backed previews (HTML) for the same file.
    var onDidWriteToDisk: ((URL) -> Void)?
    /// Clear the preview (no active tab).
    var onClearPreview: (() -> Void)?
    /// Update the sidebar's selected file to match the given tab.
    var onSyncSidebarSelection: ((EditorTab) -> Void)?
    /// Update `selectedFileID` on AppState.
    var onSetSelectedFileID: ((URL?) -> Void)?
    /// Begin security-scoped access.
    var onBeginAccessing: ((URL) -> Void)?
    /// End security-scoped access.
    var onEndAccessing: ((URL) -> Void)?
    /// Returns true if the URL is outside the project root (sandbox).
    var onRequiresDirectFileAccess: ((URL) -> Bool)?
    /// Record the last-known modification date for external-change detection.
    var onRecordModDate: ((URL) -> Void)?
    /// Surface an error to the user.
    var onReport: ((AppError) -> Void)?
    var onDidSave: (() -> Void)?

    // MARK: - Init

    init(fileService: FileServiceProtocol) {
        self.fileService = fileService
    }

    // MARK: - Computed

    var selectedTab: EditorTab? { openTabs.first { $0.id == selectedTabID } }

    // MARK: - Open

    func openFile(_ item: FileItem) {
        guard !item.isDirectory else { return }
        let attrs = fileService.attributes(at: item.url)
        if let size = attrs?[.size] as? Int64, size > Self.largeFileThreshold {
            pendingLargeFile = item
            showingLargeFileWarning = true
            return
        }
        openFileUnchecked(item)
    }

    func openFileUnchecked(_ item: FileItem) {
        let sid = PerformanceTracer.begin("OpenFile", log: PerformanceTracer.fileOps)
        let needsDirectAccess = onRequiresDirectFileAccess?(item.url) ?? true
        if needsDirectAccess { onBeginAccessing?(item.url) }
        onSetSelectedFileID?(item.id)

        if let existing = openTabs.first(where: { $0.url == item.url }) {
            if needsDirectAccess { onEndAccessing?(item.url) }
            selectedTabID = existing.id
            onSyncPreview?(existing)
            PerformanceTracer.end("OpenFile", log: PerformanceTracer.fileOps, id: sid)
            return
        }

        let lang = FileTypeConfiguration.shared.editorLanguage(for: item.fileExtension) ?? .markdown
        let tab = EditorTab(url: item.url, content: "", language: lang, awaitingInitialContent: true)
        openTabs.insert(tab, at: 0)
        selectedTabID = tab.id
        onSyncPreview?(tab)

        let tabID = tab.id
        let url   = item.url
        let svc   = fileService

        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let content = try svc.readFile(at: url)
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
        guard let tab = openTabs.first(where: { $0.id == tabID }),
              tab.awaitingInitialContent else { return }
        tab.content = content
        tab.contentRevision &+= 1
        tab.awaitingInitialContent = false
        onRecordModDate?(tab.url)
        if selectedTabID == tabID, tab.language == .markdown { onSyncPreview?(tab) }
    }

    func failLoadingTab(tabID: UUID, url: URL, error: Error) {
        guard let idx = openTabs.firstIndex(where: { $0.id == tabID }),
              openTabs[idx].awaitingInitialContent else {
            onReport?(.fileRead(url, underlying: error))
            return
        }
        let closingURL  = openTabs[idx].url
        let wasSelected = selectedTabID == tabID
        openTabs.remove(at: idx)
        onEndAccessing?(closingURL)

        if wasSelected {
            if idx < openTabs.count      { selectedTabID = openTabs[idx].id }
            else if !openTabs.isEmpty    { selectedTabID = openTabs.last?.id }
            else                         { selectedTabID = nil; onClearPreview?() }
            if let t = selectedTab { onSyncSidebarSelection?(t); onSyncPreview?(t) }
            else                   { onSetSelectedFileID?(nil) }
        }
        onReport?(.fileRead(url, underlying: error))
    }

    // MARK: - Close

    func closeTab(_ tabID: UUID) {
        guard let tab = openTabs.first(where: { $0.id == tabID }) else { return }
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
        onEndAccessing?(closingURL)

        recentlyClosedURLs.append(closingURL)
        if recentlyClosedURLs.count > Self.recentlyClosedLimit { recentlyClosedURLs.removeFirst() }

        if selectedTabID == tabID {
            if idx < openTabs.count   { selectedTabID = openTabs[idx].id }
            else if !openTabs.isEmpty { selectedTabID = openTabs.last?.id }
            else                      { selectedTabID = nil; onClearPreview?() }
        }
        if let t = selectedTab { onSyncSidebarSelection?(t); onSyncPreview?(t) }
        else                   { onSetSelectedFileID?(nil) }
    }

    // MARK: - Content

    func updateTabContent(_ tabID: UUID, content: String) {
        guard let tab = openTabs.first(where: { $0.id == tabID }) else { return }
        tab.content = content
        tab.contentRevision &+= 1
        tab.isModified = true
        tab.awaitingInitialContent = false
        onScheduleSessionPersist?()
        if selectedTabID == tabID { onSyncPreview?(tab) }
    }

    func saveTab(_ tab: EditorTab) {
        guard tab.isModified else { return }
        // 乐观更新 UI：先清除修改标记，避免用户连续触发多次写入
        tab.isModified = false
        let content = tab.content
        let url     = tab.url
        let svc     = fileService
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                try svc.writeFile(at: url, content: content)
                await self?.didSaveTab(tab, url: url)
            } catch {
                // 写入失败：回滚修改标记并报错
                await self?.didFailSaveTab(tab, url: url, error: error)
            }
        }
    }

    @MainActor
    private func didSaveTab(_ tab: EditorTab, url: URL) {
        if tab.id == selectedTabID { onSyncPreview?(tab) }
        onDidWriteToDisk?(url)
        onDidSave?()
    }

    @MainActor
    private func didFailSaveTab(_ tab: EditorTab, url: URL, error: Error) {
        tab.isModified = true   // 回滚乐观更新
        onReport?(.fileWrite(url, underlying: error))
    }

    func saveCurrentTab() {
        guard let tab = selectedTab else { return }
        saveTab(tab)
    }

    // MARK: - Selection

    func selectTab(_ id: UUID) {
        selectedTabID = id
        if let tab = selectedTab { onSyncSidebarSelection?(tab); onSyncPreview?(tab) }
    }

    func syncSidebarSelectionToTab(_ tab: EditorTab) {
        // Sidebar selection is AppState.selectedFileID; we just notify the coordinator.
        onSyncSidebarSelection?(tab)
    }

    // MARK: - Navigation

    func reopenLastClosedTab() {
        while let url = recentlyClosedURLs.popLast() {
            guard fileService.fileExists(at: url) else { continue }
            if openTabs.contains(where: { $0.url == url }) { continue }
            openFile(FileItem(url: url, isDirectory: false))
            return
        }
    }

    func selectNextTab() {
        guard openTabs.count > 1, let id = selectedTabID,
              let idx = openTabs.firstIndex(where: { $0.id == id }) else { return }
        selectTab(openTabs[(idx + 1) % openTabs.count].id)
    }

    func selectPreviousTab() {
        guard openTabs.count > 1, let id = selectedTabID,
              let idx = openTabs.firstIndex(where: { $0.id == id }) else { return }
        selectTab(openTabs[(idx - 1 + openTabs.count) % openTabs.count].id)
    }

    func moveTab(from src: Int, to dst: Int) {
        guard src >= 0, src < openTabs.count,
              dst >= 0, dst < openTabs.count else { return }
        let tab = openTabs.remove(at: src)
        openTabs.insert(tab, at: dst)
    }
}
