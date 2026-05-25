import Foundation
import Observation

enum EditorLanguage: String {
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

    private var accessedURLs: Set<URL> = []

    func beginAccessing(_ url: URL) {
        if url.startAccessingSecurityScopedResource() {
            accessedURLs.insert(url)
        }
    }

    func endAccessing(_ url: URL) {
        if accessedURLs.remove(url) != nil {
            url.stopAccessingSecurityScopedResource()
        }
    }

    deinit {
        for url in accessedURLs {
            url.stopAccessingSecurityScopedResource()
        }
    }

    // MARK: - Tab close confirmation

    var pendingCloseTab: EditorTab?
    var showingCloseConfirmation = false

    private let fileService: FileServiceProtocol
    let fileWatcher = FileWatcherService()

    init(fileService: FileServiceProtocol = FileService()) {
        self.fileService = fileService
    }

    func setError(_ message: String) {
        errorMessage = message
    }
    @ObservationIgnored private var previewUpdateTask: Task<Void, Never>?

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
        // Pre-load one more level for sidebar expand indicators
        for item in children where item.isDirectory {
            let subChildren = fileService.loadImmediateChildren(of: item.url)
            item.children = subChildren
            addToMap(subChildren)
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

        selectedFileID = item.id

        // Check if already open
        if let existing = openTabs.first(where: { $0.url == item.url }) {
            selectedTabID = existing.id
            syncPreviewContent(from: existing)
            return
        }

        do {
            let content = try fileService.readFile(at: item.url)
            let lang = FileTypeConfiguration.shared.editorLanguage(for: item.fileExtension) ?? .markdown
            let tab = EditorTab(url: item.url, content: content, language: lang)
            openTabs.append(tab)
            selectedTabID = tab.id
            syncPreviewContent(from: tab)
        } catch {
            setError("Failed to open “\(item.name)”: \(error.localizedDescription)")
        }
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

        openTabs.remove(at: idx)

        if selectedTabID == tabID {
            if idx < openTabs.count {
                selectedTabID = openTabs[idx].id
            } else if !openTabs.isEmpty {
                selectedTabID = openTabs.last?.id
            } else {
                selectedTabID = nil
                previewContent = ""
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

        if tabID == selectedTabID {
            schedulePreviewUpdate(content: content, language: openTabs[idx].language)
        }
    }

    private func schedulePreviewUpdate(content: String, language: EditorLanguage) {
        previewUpdateTask?.cancel()
        previewUpdateTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            previewContent = content
            previewLanguage = language
        }
    }

    func saveTab(_ tab: EditorTab) {
        guard tab.isModified else { return }
        do {
            try fileService.writeFile(at: tab.url, content: tab.content)
            if let idx = openTabs.firstIndex(where: { $0.id == tab.id }) {
                openTabs[idx].isModified = false
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
        previewContent = tab.content
        previewLanguage = tab.language
    }
}
