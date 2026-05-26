import Foundation
import Observation

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

@Observable
final class AppState {
    var fileTree: [FileItem] = []
    var fileItemMap: [UUID: FileItem] = [:]
    var selectedFileID: UUID?
    var rootURL: URL?
    var openTabs: [EditorTab] = []
    var selectedTabID: UUID?
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
    var editorScrollPercent: Double = 0
    var previewScrollPercent: Double = 0
    var isSyncingScroll = false

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

    private let fileService: FileServiceProtocol
    let fileWatcher = FileWatcherService()
    let themeStore: PreviewThemeStore
    let previewExporter = PreviewExporter()

    init(fileService: FileServiceProtocol = FileService(),
         themeStore: PreviewThemeStore = PreviewThemeStore()) {
        self.fileService = fileService
        self.themeStore = themeStore
    }

    func setError(_ message: String) {
        errorMessage = message
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
        openTabs.append(tab)
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
        let displayName = item.name
        let service = fileService

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let content = try service.readFile(at: url)
                DispatchQueue.main.async {
                    self?.applyLoadedContent(tabID: tabID, content: content)
                }
            } catch {
                DispatchQueue.main.async {
                    self?.failLoadingTab(tabID: tabID, name: displayName, error: error)
                }
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

    private func failLoadingTab(tabID: UUID, name: String, error: Error) {
        guard let idx = openTabs.firstIndex(where: { $0.id == tabID }) else {
            // Tab was already closed or never inserted; just surface the error.
            setError("Failed to open “\(name)”: \(error.localizedDescription)")
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
                syncPreviewContent(from: tab)
            }
        }

        setError("Failed to open “\(name)”: \(error.localizedDescription)")
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
            syncPreviewContent(from: newTab)
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
            setError("Failed to save “\(tab.name)”: \(error.localizedDescription)")
        }
    }

    func saveCurrentTab() {
        guard let tab = selectedTab else { return }
        saveTab(tab)
    }

    func selectTab(_ id: UUID) {
        selectedTabID = id
        if let tab = selectedTab {
            syncPreviewContent(from: tab)
        }
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
