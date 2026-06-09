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
        didSet {
            syncShareServerState()
            if !isRestoringSession { persistSession() }
        }
    }
    var openTabs: [EditorTab] = [] {
        didSet {
            syncShareServerState()
            if !isRestoringSession { persistSession() }
        }
    }
    var selectedTabID: UUID? {
        didSet { if !isRestoringSession { persistSession() } }
    }
    var previewContent: String = ""
    var previewLanguage: EditorLanguage = .markdown
    var previewMode: PreviewMode = .empty {
        didSet {
            previewFindController.activeMode = previewMode
            if previewMode == .empty {
                previewFindController.close()
            }
        }
    }
    var previewHTMLFileURL: URL?
    var previewReloadToken: Int = 0
    var errorMessage: String?

    // MARK: - Cursor / Status

    var cursorLine: Int = 1
    var cursorColumn: Int = 1
    var editorVisibleLine: Int = 0
    var previewVisibleLine: Int = 0
    var editorScrollCommand: ScrollSyncCommand = .idle
    var previewScrollCommand: ScrollSyncCommand = .idle

    func updateCursorPosition(line: Int, column: Int) {
        cursorLine = line
        cursorColumn = column
    }

    func requestEditorScroll(to line: Int) {
        guard line >= 0 else { return }
        editorScrollCommand = editorScrollCommand.advanced(to: line)
    }

    func requestPreviewScroll(to line: Int) {
        guard line >= 0 else { return }
        previewScrollCommand = previewScrollCommand.advanced(to: line)
    }

    var currentFileSize: String {
        guard let tab = selectedTab else { return "" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(tab.content.utf8.count))
    }

    // MARK: - Security Scoped Resources

    @ObservationIgnored
    private var accessRefCounts: [URL: Int] = [:]

    @ObservationIgnored
    var isRestoringSession = false

    func beginAccessing(_ url: URL) {
        let scopedURL = url.standardizedFileURL
        if let count = accessRefCounts[scopedURL] {
            accessRefCounts[scopedURL] = count + 1
            return
        }
        if scopedURL.startAccessingSecurityScopedResource() {
            accessRefCounts[scopedURL] = 1
        }
    }

    func endAccessing(_ url: URL) {
        let scopedURL = url.standardizedFileURL
        guard let count = accessRefCounts[scopedURL] else { return }
        if count > 1 {
            accessRefCounts[scopedURL] = count - 1
            return
        }
        accessRefCounts.removeValue(forKey: scopedURL)
        scopedURL.stopAccessingSecurityScopedResource()
    }

    deinit {
        autoSaveTimer?.invalidate()
        if let autoSaveObserver {
            NotificationCenter.default.removeObserver(autoSaveObserver)
        }
        for url in accessRefCounts.keys {
            url.stopAccessingSecurityScopedResource()
        }
    }

    // MARK: - Tab close confirmation

    var pendingCloseTab: EditorTab?
    var showingCloseConfirmation = false

    @ObservationIgnored
    var recentlyClosedURLs: [URL] = []
    static let recentlyClosedLimit = 16

    var showingQuickOpen = false

    let fileService: FileServiceProtocol
    let fileWatcher: any FileWatcherServiceProtocol
    let themeStore: PreviewThemeStore
    let previewExporter = PreviewExporter()
    let previewFindController = PreviewFindController()
    let sessionStore: SessionStore
    let shareServer = LocalShareServer()

    @ObservationIgnored
    private var autoSaveTimer: Timer?

    init(fileService: FileServiceProtocol = FileService(),
         fileWatcher: any FileWatcherServiceProtocol = FileWatcherService(),
         themeStore: PreviewThemeStore = PreviewThemeStore(),
         sessionStore: SessionStore = SessionStore()) {
        self.fileService = fileService
        self.fileWatcher = fileWatcher
        self.themeStore = themeStore
        self.sessionStore = sessionStore
        setupAutoSaveTimer()
    }

    // MARK: - Auto Save

    @ObservationIgnored
    private var autoSaveObserver: Any?

    func setupAutoSaveTimer() {
        autoSaveTimer?.invalidate()
        autoSaveTimer = nil
        let settings = AppSettings.shared
        guard settings.autoSave else { return }
        autoSaveTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(settings.autoSaveInterval), repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.autoSaveModifiedTabs()
            }
        }
        if autoSaveObserver == nil {
            autoSaveObserver = NotificationCenter.default.addObserver(forName: .autoSaveSettingsChanged, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.setupAutoSaveTimer()
                }
            }
        }
    }

    private func autoSaveModifiedTabs() {
        for tab in openTabs where tab.isModified {
            saveTab(tab)
        }
    }

    func setError(_ message: String) {
        errorMessage = message
    }

    func report(_ error: AppError, logger: Logger = AppLog.app) {
        AppLog.error(error, in: logger)
        if error.severity == .user {
            errorMessage = error.errorDescription
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
        let normalizedURL = url.standardizedFileURL
        let previousRoot = rootURL?.standardizedFileURL
        if previousRoot != normalizedURL {
            beginAccessing(normalizedURL)
        }

        rootURL = url
        if let previousRoot, previousRoot != normalizedURL {
            endAccessing(previousRoot)
        }
        openTabs.forEach { endAccessing($0.url) }
        openTabs.removeAll()
        selectedTabID = nil
        selectedFileID = nil
        previewContent = ""
        previewHTMLFileURL = nil
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

    func isSameOrDescendant(_ url: URL, of baseURL: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let basePath = baseURL.standardizedFileURL.path
        return path == basePath || path.hasPrefix(basePath + "/")
    }

    func replacingDescendantURL(_ url: URL, from oldBaseURL: URL, to newBaseURL: URL) -> URL? {
        let oldBasePath = oldBaseURL.standardizedFileURL.path
        let sourcePath = url.standardizedFileURL.path
        guard sourcePath == oldBasePath || sourcePath.hasPrefix(oldBasePath + "/") else { return nil }
        let suffix = sourcePath.dropFirst(oldBasePath.count)
        guard !suffix.isEmpty else { return newBaseURL.standardizedFileURL }
        return newBaseURL.standardizedFileURL.appendingPathComponent(
            String(suffix.drop(while: { $0 == "/" }))
        )
    }

    func requiresDirectFileAccess(_ url: URL) -> Bool {
        guard let rootURL else { return true }
        return !isSameOrDescendant(url, of: rootURL)
    }

    func syncShareServerState() {
        guard shareServer.isRunning else { return }

        if shareServer.rootURL?.standardizedFileURL != rootURL?.standardizedFileURL {
            shareServer.rootURL = rootURL
        }

        let currentAllowedFiles = openTabs.map(\.url.standardizedFileURL)
        let existingAllowedFiles = shareServer.allowedFiles.map(\.standardizedFileURL)
        if currentAllowedFiles != existingAllowedFiles {
            shareServer.allowedFiles = openTabs.map(\.url)
        }
    }

    func handleItemRenamed(from oldURL: URL, to newURL: URL) {
        let oldURL = oldURL.standardizedFileURL
        let newURL = newURL.standardizedFileURL

        if let selectedFileID,
           let replaced = replacingDescendantURL(selectedFileID, from: oldURL, to: newURL) {
            self.selectedFileID = replaced
        }

        if let previewHTMLFileURL,
           let replaced = replacingDescendantURL(previewHTMLFileURL, from: oldURL, to: newURL) {
            self.previewHTMLFileURL = replaced
        }

        for idx in openTabs.indices {
            if let replaced = replacingDescendantURL(openTabs[idx].url, from: oldURL, to: newURL) {
                openTabs[idx].url = replaced
            }
        }

        recentlyClosedURLs = recentlyClosedURLs.compactMap {
            replacingDescendantURL($0, from: oldURL, to: newURL)
        }

        if let tab = selectedTab {
            syncPreviewContent(from: tab)
        }
    }

    func handleItemDeleted(at deletedURL: URL) {
        let deletedURL = deletedURL.standardizedFileURL

        let removedTabs = openTabs.filter { isSameOrDescendant($0.url, of: deletedURL) }
        for tab in removedTabs {
            endAccessing(tab.url)
        }
        openTabs.removeAll { isSameOrDescendant($0.url, of: deletedURL) }
        recentlyClosedURLs.removeAll { isSameOrDescendant($0, of: deletedURL) }

        if let selectedFileID, isSameOrDescendant(selectedFileID, of: deletedURL) {
            self.selectedFileID = nil
        }

        if let selectedTabID,
           !openTabs.contains(where: { $0.id == selectedTabID }) {
            self.selectedTabID = openTabs.first?.id
        }

        if let tab = selectedTab {
            syncSidebarSelectionToTab(tab)
            syncPreviewContent(from: tab)
        } else {
            selectedTabID = nil
            previewContent = ""
            previewHTMLFileURL = nil
            previewMode = .empty
        }
    }

    // MARK: - Preview

    func syncPreviewContent(from tab: EditorTab) {
        previewLanguage = tab.language
        if tab.language == .html {
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
