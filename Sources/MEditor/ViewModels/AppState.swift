import Foundation
import Observation
import OSLog

enum EditorLanguage: String {
    case markdown
    case html
}

/// What the preview pane is currently showing. Drives PreviewPanel's view selection
/// without relying on string-based sentinels.
enum PreviewMode: Equatable {
    case empty
    case markdown
    case html
}

@MainActor
@Observable
final class AppState {
    var fileTree: [FileItem] = []
    var fileItemMap: [URL: FileItem] = [:]
    var selectedFileID: URL?
    var rootURL: URL? {
        didSet { if !isRestoringSession { persistSession() } }
    }
    var openTabs: [EditorTab] = [] {
        didSet { if !isRestoringSession { persistSession() } }
    }
    var selectedTabID: UUID? {
        didSet { if !isRestoringSession { persistSession() } }
    }
    var previewContent: String = ""
    var previewLanguage: EditorLanguage = .markdown
    /// What the preview is currently showing. Replaces the previous
    /// `previewContent.isEmpty` + sentinel-string pattern.
    var previewMode: PreviewMode = .empty
    /// File URL of the currently previewed HTML document.
    /// Set immediately when an HTML file is selected (no need to wait for
    /// Swift-side file read), so WKWebView can `loadFileURL` in parallel
    /// with the editor's read.
    var previewHTMLFileURL: URL?
    /// Bumped when the active HTML file is saved or externally modified, so
    /// the preview re-loads (file URL alone isn't enough to invalidate).
    var previewReloadToken: Int = 0
    var errorMessage: String?

    // MARK: - Cursor / Status

    var cursorLine: Int = 1
    var cursorColumn: Int = 1
    /// Source line at the top of the editor's viewport. Drives editor→preview sync.
    var editorVisibleLine: Int = 0
    /// Source line at the top of the preview's viewport. Drives preview→editor sync.
    var previewVisibleLine: Int = 0

    func updateCursorPosition(line: Int, column: Int) {
        cursorLine = line
        cursorColumn = column
    }

    var currentFileSize: String {
        guard let tab = selectedTab else { return "" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(tab.content.utf8.count))
    }

    // MARK: - Security Scoped Resources
    //
    // macOS hands us security-scoped URLs from NSOpenPanel, drag-and-drop and
    // `onOpenURL`. Each `startAccessingSecurityScopedResource()` must be paired
    // with a `stopAccessingSecurityScopedResource()`, otherwise the entitlement
    // is held forever (memory + sandbox quota cost).
    //
    // We may be asked to begin accessing the same URL multiple times (e.g.
    // user opens folder, then opens a file under it). Track a refcount so
    // we only call stop when the last consumer releases.

    @ObservationIgnored
    private var accessRefCounts: [URL: Int] = [:]

    /// Suppresses automatic `persistSession()` calls during `restoreSession()`.
    @ObservationIgnored
    private var isRestoringSession = false

    func beginAccessing(_ url: URL) {
        if let count = accessRefCounts[url] {
            accessRefCounts[url] = count + 1
            return
        }
        if url.startAccessingSecurityScopedResource() {
            accessRefCounts[url] = 1
        }
    }

    func endAccessing(_ url: URL) {
        guard let count = accessRefCounts[url] else { return }
        if count > 1 {
            accessRefCounts[url] = count - 1
            return
        }
        accessRefCounts.removeValue(forKey: url)
        url.stopAccessingSecurityScopedResource()
    }

    deinit {
        for url in accessRefCounts.keys {
            url.stopAccessingSecurityScopedResource()
        }
    }

    // MARK: - Tab close confirmation

    var pendingCloseTab: EditorTab?
    var showingCloseConfirmation = false

    /// Stack of URLs from recently closed tabs, used by ⌘⇧T to reopen.
    /// Capped to avoid unbounded growth in long sessions.
    @ObservationIgnored
    private var recentlyClosedURLs: [URL] = []
    private static let recentlyClosedLimit = 16

    /// True when user invoked Quick Open (⌘P) and the picker should appear.
    var showingQuickOpen = false

    private let fileService: FileServiceProtocol
    let fileWatcher = FileWatcherService()
    let themeStore: PreviewThemeStore
    let previewExporter = PreviewExporter()
    private let sessionStore: SessionStore

    init(fileService: FileServiceProtocol = FileService(),
         themeStore: PreviewThemeStore = PreviewThemeStore(),
         sessionStore: SessionStore = SessionStore()) {
        self.fileService = fileService
        self.themeStore = themeStore
        self.sessionStore = sessionStore
    }

    func setError(_ message: String) {
        errorMessage = message
    }

    /// Report a typed `AppError`: always log to OSLog; surface to the user
    /// via Alert only when severity is `.user`.
    func report(_ error: AppError, logger: Logger = AppLog.app) {
        AppLog.error(error, in: logger)
        if error.severity == .user {
            errorMessage = error.errorDescription
        }
    }

    // MARK: - Session persistence

    private var sessionSnapshot: (urls: [URL], selectedIndex: Int?) {
        let urls = openTabs.map { $0.url }
        let selectedIdx: Int? = {
            guard let id = selectedTabID else { return nil }
            return openTabs.firstIndex(where: { $0.id == id })
        }()
        return (urls, selectedIdx)
    }

    /// Schedule a debounced save of the current session shape (root folder,
    /// open tabs, selected tab). Safe to call from any state-change site.
    private func persistSession() {
        let snapshot = sessionSnapshot
        sessionStore.scheduleSave(
            rootURL: rootURL,
            openTabURLs: snapshot.urls,
            selectedIndex: snapshot.selectedIndex
        )
    }

    /// Force an immediate synchronous save — call before the app quits.
    func flushSession() {
        let snapshot = sessionSnapshot
        sessionStore.saveNow(
            rootURL: rootURL,
            openTabURLs: snapshot.urls,
            selectedIndex: snapshot.selectedIndex
        )
    }

    /// Restore a previously persisted session if any. Silently no-ops on
    /// first launch or if every bookmark has gone stale / been revoked.
    /// Should be called once at app startup, after `AppState` is built.
    func restoreSession() {
        guard let session = sessionStore.load() else { return }
        isRestoringSession = true
        defer { isRestoringSession = false }

        // 1. Restore root folder
        if let rootData = session.rootBookmark,
           let resolved = SessionStore.resolveBookmark(rootData),
           FileManager.default.fileExists(atPath: resolved.url.path) {
            beginAccessing(resolved.url)
            openFolder(resolved.url)
        }

        // 2. Restore tabs (skip ones whose files vanished or are already
        //    open from this launch — e.g. the user double-clicked a .md file
        //    which fired `onOpenURL` before `onAppear`/restoreSession).
        let alreadyOpenURLs = Set(openTabs.map { $0.url })
        var restoredTabs: [(EditorTab, URL)] = []
        for tabBookmark in session.tabs {
            guard let resolved = SessionStore.resolveBookmark(tabBookmark) else { continue }
            let url = resolved.url
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            guard !url.hasDirectoryPath else { continue }
            // Dedup: skip URLs already added by an earlier code path.
            if alreadyOpenURLs.contains(url) { continue }

            beginAccessing(url)
            let lang = FileTypeConfiguration.shared
                .editorLanguage(for: url.pathExtension.lowercased()) ?? .markdown
            let tab = EditorTab(url: url, content: "", language: lang)
            restoredTabs.append((tab, url))
        }
        // Restored tabs go AFTER any newly-opened tabs in this launch.
        // Newest-left ordering: the file the user just double-clicked
        // (already in openTabs from onOpenURL) stays at index 0;
        // previously-open tabs follow on the right in their saved order.
        openTabs.append(contentsOf: restoredTabs.map { $0.0 })

        // 3. Restore selected tab (clamp index to bounds). If the user
        //    already has a tab selected (e.g. opened from `onOpenURL`),
        //    keep their selection — don't override.
        if selectedTabID == nil,
           let idx = session.selectedTabIndex,
           idx >= 0, idx < restoredTabs.count {
            let restoredTab = restoredTabs[idx].0
            selectedTabID = restoredTab.id
            syncSidebarSelectionToTab(restoredTab)
            syncPreviewContent(from: restoredTab)
        }

        // 4. Read each restored tab's contents asynchronously.
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

    var selectedTab: EditorTab? {
        get { openTabs.first { $0.id == selectedTabID } }
        set {
            guard let newValue else {
                selectedTabID = nil
                return
            }
            selectedTabID = newValue.id
        }
    }

    // MARK: - File tree

    func openFolder(_ url: URL) {
        rootURL = url
        // Clear tabs from the previous folder.
        openTabs.forEach { endAccessing($0.url) }
        openTabs.removeAll()
        selectedTabID = nil
        previewMode = .empty
        reloadFileTree()
        fileWatcher.startWatching(urls: [url]) { [weak self] in
            self?.reloadFileTree()
        }
    }

    func reloadFileTree() {
        guard let rootURL else { return }
        fileItemMap = [:]
        let children = fileService.loadImmediateChildren(of: rootURL)
        fileTree = children
        addToMap(children)
        // Recursively load subtree for full hierarchy display.
        // Depth-limited to avoid hanging on huge trees.
        for item in children where item.isDirectory {
            loadSubtree(item, depth: 1, maxDepth: 6)
        }
    }

    private func loadSubtree(_ item: FileItem, depth: Int, maxDepth: Int) {
        guard depth <= maxDepth else { return }
        let subChildren = fileService.loadImmediateChildren(of: item.url)
        item.children = subChildren
        addToMap(subChildren)
        for child in subChildren where child.isDirectory {
            loadSubtree(child, depth: depth + 1, maxDepth: maxDepth)
        }
    }

    func selectFile(_ item: FileItem) {
        if item.isDirectory {
            selectedFileID = item.id
        } else {
            openFile(item)
        }
    }

    private func addToMap(_ items: [FileItem]) {
        for item in items {
            fileItemMap[item.id] = item
        }
    }

    // MARK: - Tabs

    func openFile(_ item: FileItem) {
        guard !item.isDirectory else { return }

        // Hold a security-scoped reference for as long as a tab references this URL.
        // Released in performCloseTab / failLoadingTab.
        beginAccessing(item.url)

        selectedFileID = item.id

        // Already open? Just switch tabs and sync the preview.
        if let existing = openTabs.first(where: { $0.url == item.url }) {
            // We took an extra reference above; release it now since the tab
            // already holds one.
            endAccessing(item.url)
            selectedTabID = existing.id
            syncPreviewContent(from: existing)
            return
        }

        // Optimistic: create a tab with empty content immediately so the UI
        // (tab bar, editor, preview) reacts on the next runloop tick. The
        // file body arrives asynchronously below.
        let lang = FileTypeConfiguration.shared.editorLanguage(for: item.fileExtension) ?? .markdown
        let tab = EditorTab(url: item.url, content: "", language: lang)
        // Newest tabs go to the left (index 0). Pre-existing tabs shift right.
        openTabs.insert(tab, at: 0)
        selectedTabID = tab.id

        // For HTML files, kick off WKWebView.loadFileURL immediately by
        // exposing the URL — this proceeds in parallel with the Swift-side
        // file read and avoids the IPC string transfer cost entirely.
        if lang == .html {
            previewHTMLFileURL = item.url
            previewLanguage = .html
            previewMode = .html
            previewReloadToken &+= 1
            previewContent = ""
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
        }

    }

    private func applyLoadedContent(tabID: UUID, content: String) {
        guard let idx = openTabs.firstIndex(where: { $0.id == tabID }) else { return }
        openTabs[idx].content = content
        if selectedTabID == tabID {
            syncPreviewContent(from: openTabs[idx])
        }
    }

    private func failLoadingTab(tabID: UUID, url: URL, error: Error) {
        guard let idx = openTabs.firstIndex(where: { $0.id == tabID }) else {
            // Tab was already closed or never inserted; just surface the error.
            report(.fileRead(url, underlying: error), logger: AppLog.file)
            return
        }

        let closingURL = openTabs[idx].url
        let wasSelected = (selectedTabID == tabID)
        openTabs.remove(at: idx)
        endAccessing(closingURL)

        if wasSelected {
            // Pick the tab that visually replaces the failed one: prefer the
            // tab now occupying the same index (next), otherwise fall back to
            // the one before it. If user already switched to another tab while
            // this one was loading, leave their choice alone.
            if idx < openTabs.count {
                selectedTabID = openTabs[idx].id
            } else if !openTabs.isEmpty {
                selectedTabID = openTabs[openTabs.count - 1].id
            } else {
                selectedTabID = nil
                previewContent = ""
                previewHTMLFileURL = nil
                previewMode = .empty
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

    private func performCloseTab(_ tabID: UUID) {
        guard let idx = openTabs.firstIndex(where: { $0.id == tabID }) else { return }

        let closingURL = openTabs[idx].url
        openTabs.remove(at: idx)
        // Pair the beginAccessing call from openFile.
        endAccessing(closingURL)

        // Push onto recently-closed stack for ⌘⇧T (reopen).
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
                previewContent = ""
                previewHTMLFileURL = nil
                previewMode = .empty
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
        openTabs[idx].isModified = true
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

    /// Highlight the sidebar row for the given tab's URL, so clicking through
    /// the tab bar keeps the file tree in sync.
    private func syncSidebarSelectionToTab(_ tab: EditorTab) {
        // FileItem.id is now URL, so this is a direct lookup — no scan.
        if fileItemMap[tab.url] != nil {
            selectedFileID = tab.url
        }
    }

    /// Reopen the most recently closed tab. No-op if the stack is empty
    /// or if the file no longer exists on disk.
    func reopenLastClosedTab() {
        while let url = recentlyClosedURLs.popLast() {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            // Don't reopen if it's already open.
            if openTabs.contains(where: { $0.url == url }) { continue }
            openFile(FileItem(url: url, isDirectory: false))
            return
        }
    }

    /// Switch to the next tab, wrapping around at the end. No-op if 0 or 1 tabs.
    func selectNextTab() {
        guard openTabs.count > 1, let id = selectedTabID,
              let idx = openTabs.firstIndex(where: { $0.id == id }) else { return }
        let nextIdx = (idx + 1) % openTabs.count
        selectTab(openTabs[nextIdx].id)
    }

    /// Switch to the previous tab, wrapping around at the start.
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

    // MARK: - Private

    private func syncPreviewContent(from tab: EditorTab) {
        previewLanguage = tab.language
        if tab.language == .html {
            // HTML preview is URL-driven: WKWebView loadFileURL reads from disk
            // directly, much faster than IPC-transferring the file content.
            previewHTMLFileURL = tab.url
            previewReloadToken &+= 1
            previewContent = ""
            previewMode = .html
        } else {
            previewHTMLFileURL = nil
            previewContent = tab.content
            previewMode = tab.content.isEmpty ? .empty : .markdown
        }
    }
}
