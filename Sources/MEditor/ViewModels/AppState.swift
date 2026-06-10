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
    var indexedFiles: [FileItem] = []
    var selectedFileID: URL?
    var rootURL: URL? {
        didSet {
            syncShareServerState()
            if !isRestoringSession { scheduleSessionPersist() }
        }
    }
    var openTabs: [EditorTab] = [] {
        didSet {
            syncShareServerState()
            if !isRestoringSession { scheduleSessionPersist() }
        }
    }
    var selectedTabID: UUID? {
        didSet { if !isRestoringSession { scheduleSessionPersist() } }
    }

    /// Coalesce multiple state changes within the same runloop tick into a
    /// single persistSession call. Without this, operations like restoring
    /// 10 tabs fire persistSession 10× in one frame.
    @ObservationIgnored
    private var sessionPersistScheduled = false

    private func scheduleSessionPersist() {
        guard !sessionPersistScheduled else { return }
        sessionPersistScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.sessionPersistScheduled = false
            self.persistSession()
        }
    }
    var previewContent: String = ""
    var previewContentRevision: Int = 0
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

    @ObservationIgnored
    private var pendingTreeReloadWorkItem: DispatchWorkItem?

    @ObservationIgnored
    private var fileIndexGeneration = 0

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
        clearPreview()
        reloadFileTree()
        fileWatcher.startWatching(urls: [url]) { [weak self] in
            self?.scheduleWatchedTreeReload()
        }
    }

    func reloadFileTree() {
        guard let rootURL else { return }
        let sid = PerformanceTracer.begin("ReloadFileTree", log: PerformanceTracer.fileOps)
        defer { PerformanceTracer.end("ReloadFileTree", log: PerformanceTracer.fileOps, id: sid) }

        pendingTreeReloadWorkItem?.cancel()
        fileItemMap = [:]
        let children = fileService.loadImmediateChildren(of: rootURL)
        fileTree = children
        addToMap(children)
        rebuildFileIndex(for: rootURL)
    }

    func loadChildrenIfNeeded(for item: FileItem) {
        guard item.isDirectory, !item.childrenLoaded, !item.isLoadingChildren else { return }
        item.isLoadingChildren = true
        let service = fileService
        let url = item.url
        Task.detached(priority: .userInitiated) { [weak self] in
            let children = service.loadImmediateChildren(of: url)
            await self?.applyLoadedChildren(children, to: item, expectedURL: url)
        }
    }

    private func scheduleWatchedTreeReload() {
        pendingTreeReloadWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.reloadFileTree()
        }
        pendingTreeReloadWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
    }

    private func rebuildFileIndex(for rootURL: URL) {
        let sid = PerformanceTracer.begin("RebuildFileIndex", log: PerformanceTracer.fileOps)
        fileIndexGeneration &+= 1
        let generation = fileIndexGeneration
        let service = fileService
        indexedFiles = []
        Task.detached(priority: .utility) { [weak self] in
            let files = service.loadAllFiles(under: rootURL)
            await self?.applyIndexedFiles(files, generation: generation, rootURL: rootURL)
            await MainActor.run {
                PerformanceTracer.end("RebuildFileIndex", log: PerformanceTracer.fileOps, id: sid)
            }
        }
    }

    private func applyLoadedChildren(_ children: [FileItem], to item: FileItem, expectedURL: URL) {
        guard item.url == expectedURL else { return }
        item.children = children
        item.childrenLoaded = true
        item.isLoadingChildren = false
        addToMap(children)
    }

    private func applyIndexedFiles(_ files: [FileItem], generation: Int, rootURL: URL) {
        guard generation == fileIndexGeneration else { return }
        guard self.rootURL?.standardizedFileURL == rootURL.standardizedFileURL else { return }
        indexedFiles = files
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
            clearPreview()
        }
    }

    // MARK: - Preview

    @discardableResult
    func clearPreview() -> Bool {
        var changed = false
        if !previewContent.isEmpty {
            previewContent = ""
            changed = true
        }
        if previewHTMLFileURL != nil {
            previewHTMLFileURL = nil
            changed = true
        }
        if previewMode != .empty {
            previewMode = .empty
            changed = true
        }
        if changed {
            previewContentRevision &+= 1
        }
        return changed
    }

    @discardableResult
    func showMarkdownPreview(content: String) -> Bool {
        var changed = false
        let nextMode: PreviewMode = .markdown
        if previewHTMLFileURL != nil {
            previewHTMLFileURL = nil
            changed = true
        }
        if previewLanguage != .markdown {
            previewLanguage = .markdown
        }
        if previewContent != content {
            previewContent = content
            changed = true
        }
        if previewMode != nextMode {
            previewMode = nextMode
            changed = true
        }
        if changed {
            previewContentRevision &+= 1
        }
        return changed
    }

    @discardableResult
    func showHTMLPreview(fileURL: URL) -> Bool {
        let normalizedURL = fileURL.standardizedFileURL
        let currentURL = previewHTMLFileURL?.standardizedFileURL
        var changed = false
        if !previewContent.isEmpty {
            previewContent = ""
            changed = true
        }
        if previewLanguage != .html {
            previewLanguage = .html
        }
        if previewMode != .html {
            previewMode = .html
            changed = true
        }
        if currentURL != normalizedURL {
            previewHTMLFileURL = fileURL
            previewReloadToken &+= 1
            changed = true
        }
        return changed
    }

    func syncPreviewContent(from tab: EditorTab) {
        let sid = PerformanceTracer.begin("SyncPreviewContent", log: PerformanceTracer.preview)
        defer { PerformanceTracer.end("SyncPreviewContent", log: PerformanceTracer.preview, id: sid) }

        if tab.language == .html {
            showHTMLPreview(fileURL: tab.url)
        } else {
            showMarkdownPreview(content: tab.content)
        }
    }
}
