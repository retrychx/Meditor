import Foundation
import Observation
import OSLog

enum EditorLanguage: String {
    case markdown
    case html
}

/// What the preview pane is currently showing.
enum PreviewMode: Equatable {
    case empty
    case markdown
    case html
}

/// Central coordinator / facade.
///
/// AppState owns the core cross-cutting state (tabs, file selection, rootURL)
/// and delegates domain-specific work to dedicated Managers:
///
///   - FileTreeManager   → file tree, lazy-load, quick-open index
///   - PreviewManager    → preview content, mode, scroll sync
///   - ShareManager      → LAN share server
///   - TemplateManager   → template picker UI + operations
///
/// Views reference `state.fileTree`, `state.previewContent`, etc. through
/// forwarding computed properties so call sites are unchanged.
@MainActor
@Observable
final class AppState {

    // MARK: - Managers

    let fileTreeManager: FileTreeManager
    let previewManager: PreviewManager
    let shareManager: ShareManager
    let templateManager: TemplateManager

    // MARK: - Core shared state

    var rootURL: URL? {
        didSet {
            shareManager.sync(rootURL: rootURL, openTabs: openTabs)
            if !isRestoringSession { scheduleSessionPersist() }
        }
    }

    var openTabs: [EditorTab] = [] {
        didSet {
            shareManager.sync(rootURL: rootURL, openTabs: openTabs)
            if !isRestoringSession { scheduleSessionPersist() }
        }
    }

    var selectedTabID: UUID? {
        didSet { if !isRestoringSession { scheduleSessionPersist() } }
    }

    var selectedFileID: URL?

    // MARK: - Cursor / Status bar

    var cursorLine: Int = 1
    var cursorColumn: Int = 1
    var editorVisibleLine: Int = 0
    var previewVisibleLine: Int = 0
    var editorScrollCommand: ScrollSyncCommand = .idle
    var previewScrollCommand: ScrollSyncCommand = .idle

    var currentFileSize: String {
        guard let tab = selectedTab else { return "" }
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: Int64(tab.content.utf8.count))
    }

    // MARK: - UI overlay state

    var errorMessage: String?
    var pendingCloseTab: EditorTab?
    var showingCloseConfirmation = false
    var pendingLargeFile: FileItem?
    var showingLargeFileWarning = false
    var showingQuickOpen = false
    var externallyModifiedTab: EditorTab?
    var showingReloadPrompt = false

    // MARK: - Services

    let fileService: FileServiceProtocol
    let fileWatcher: any FileWatcherServiceProtocol
    let themeStore: PreviewThemeStore
    let sessionStore: SessionStore

    // MARK: - Security-scoped resources

    @ObservationIgnored private var accessRefCounts: [URL: Int] = [:]

    @ObservationIgnored var isRestoringSession = false

    @ObservationIgnored var recentlyClosedURLs: [URL] = []
    static let recentlyClosedLimit = 16

    // MARK: - Session persist coalescing

    @ObservationIgnored private var sessionPersistScheduled = false

    func scheduleSessionPersist() {
        guard !sessionPersistScheduled else { return }
        sessionPersistScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.sessionPersistScheduled = false
            self.persistSession()
        }
    }

    // MARK: - Auto-save

    @ObservationIgnored private var autoSaveTimer: Timer?
    @ObservationIgnored private var autoSaveObserver: Any?

    // MARK: - Init

    init(
        fileService: FileServiceProtocol = FileService(),
        fileWatcher: any FileWatcherServiceProtocol = FileWatcherService(),
        themeStore: PreviewThemeStore = PreviewThemeStore(),
        sessionStore: SessionStore = SessionStore()
    ) {
        self.fileService = fileService
        self.fileWatcher = fileWatcher
        self.themeStore = themeStore
        self.sessionStore = sessionStore
        self.fileTreeManager = FileTreeManager(fileService: fileService)
        self.previewManager  = PreviewManager()
        self.shareManager    = ShareManager()
        self.templateManager = TemplateManager()
        setupAutoSaveTimer()
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

    // MARK: - FileTreeManager forwarding

    var fileTree: [FileItem]      { fileTreeManager.fileTree }
    var fileItemMap: [URL: FileItem] { fileTreeManager.fileItemMap }
    var indexedFiles: [FileItem]  { fileTreeManager.indexedFiles }

    func reloadFileTree() {
        guard let rootURL else { return }
        fileTreeManager.reload(rootURL: rootURL)
    }

    func loadChildrenIfNeeded(for item: FileItem) {
        fileTreeManager.loadChildrenIfNeeded(for: item)
    }

    func isSameOrDescendant(_ url: URL, of base: URL) -> Bool {
        fileTreeManager.isSameOrDescendant(url, of: base)
    }

    func replacingDescendantURL(_ url: URL, from old: URL, to new: URL) -> URL? {
        fileTreeManager.replacingDescendantURL(url, from: old, to: new)
    }

    // MARK: - PreviewManager forwarding

    var previewContent: String         { previewManager.content }
    var previewContentRevision: Int    { previewManager.contentRevision }
    var previewLanguage: EditorLanguage { previewManager.language }
    var previewMode: PreviewMode       { previewManager.mode }
    var previewHTMLFileURL: URL?       { previewManager.htmlFileURL }
    var previewReloadToken: Int        { previewManager.reloadToken }
    var previewExporter: PreviewExporter   { previewManager.exporter }
    var previewFindController: PreviewFindController { previewManager.findController }

    @discardableResult func clearPreview() -> Bool { previewManager.clear() }

    @discardableResult func showMarkdownPreview(content: String) -> Bool {
        previewManager.showMarkdown(content: content)
    }

    @discardableResult func showHTMLPreview(fileURL: URL) -> Bool {
        previewManager.showHTML(fileURL: fileURL)
    }

    func syncPreviewContent(from tab: EditorTab) {
        previewManager.sync(from: tab)
    }

    // MARK: - ShareManager forwarding

    var shareServer: ShareManager { shareManager }

    func syncShareServerState() {
        shareManager.sync(rootURL: rootURL, openTabs: openTabs)
    }

    // MARK: - TemplateManager forwarding

    var showingTemplatePicker: Bool {
        get { templateManager.showingPicker }
        set { templateManager.showingPicker = newValue }
    }
    var showingSaveTemplate: Bool {
        get { templateManager.showingSaveAs }
        set { templateManager.showingSaveAs = newValue }
    }
    var saveTemplateName: String {
        get { templateManager.saveAsName }
        set { templateManager.saveAsName = newValue }
    }
    var templateCreateParentURL: URL? {
        get { templateManager.pendingParentURL }
        set { templateManager.pendingParentURL = newValue }
    }

    // MARK: - Cursor

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

    // MARK: - Security-scoped resources

    func beginAccessing(_ url: URL) {
        let scoped = url.standardizedFileURL
        if let count = accessRefCounts[scoped] {
            accessRefCounts[scoped] = count + 1
            return
        }
        if scoped.startAccessingSecurityScopedResource() {
            accessRefCounts[scoped] = 1
        }
    }

    func endAccessing(_ url: URL) {
        let scoped = url.standardizedFileURL
        guard let count = accessRefCounts[scoped] else { return }
        if count > 1 { accessRefCounts[scoped] = count - 1; return }
        accessRefCounts.removeValue(forKey: scoped)
        scoped.stopAccessingSecurityScopedResource()
    }

    func requiresDirectFileAccess(_ url: URL) -> Bool {
        guard let rootURL else { return true }
        return !isSameOrDescendant(url, of: rootURL)
    }

    // MARK: - Error reporting

    func setError(_ message: String) { errorMessage = message }

    func report(_ error: AppError, logger: Logger = AppLog.app) {
        AppLog.error(error, in: logger)
        if error.severity == .user { errorMessage = error.errorDescription }
    }

    // MARK: - Tab computed

    var selectedTab: EditorTab? {
        get { openTabs.first { $0.id == selectedTabID } }
        set {
            guard let newValue else { selectedTabID = nil; return }
            selectedTabID = newValue.id
        }
    }

    // MARK: - Open folder

    func openFolder(_ url: URL) {
        let normalized = url.standardizedFileURL
        let previous   = rootURL?.standardizedFileURL
        if previous != normalized { beginAccessing(normalized) }

        rootURL = url
        if let previous, previous != normalized { endAccessing(previous) }

        openTabs.forEach { endAccessing($0.url) }
        openTabs.removeAll()
        selectedTabID = nil
        selectedFileID = nil
        clearPreview()
        fileTreeManager.clear()
        fileTreeManager.reload(rootURL: url)

        fileWatcher.startWatching(urls: [url]) { [weak self] in
            guard let self else { return }
            self.fileTreeManager.scheduleWatchedReload(rootURL: url)
            self.checkExternalModifications()
        }
    }

    // MARK: - File tree interaction

    func selectFile(_ item: FileItem) {
        if item.isDirectory { selectedFileID = item.id } else { openFile(item) }
    }

    // MARK: - File CRUD (used by FileSidebar)

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

    // MARK: - Templates

    func createFromTemplate(_ template: DocumentTemplate) {
        templateManager.createFromTemplate(
            template, rootURL: rootURL, fileService: fileService,
            onSuccess: { [weak self] item in
                self?.reloadFileTree()
                self?.openFile(item)
            },
            onError: { [weak self] error in
                self?.report(error, logger: AppLog.file)
            }
        )
    }

    func saveCurrentAsTemplate(name: String) {
        guard let tab = selectedTab else { return }
        do    { try templateManager.saveAs(name: name, content: tab.content) }
        catch { setError(error.localizedDescription) }
    }

    // MARK: - Cross-domain coordination

    func handleItemRenamed(from oldURL: URL, to newURL: URL) {
        let old = oldURL.standardizedFileURL
        let new = newURL.standardizedFileURL

        if let id = selectedFileID,
           let r = fileTreeManager.replacingDescendantURL(id, from: old, to: new) {
            selectedFileID = r
        }

        for tab in openTabs {
            if let r = fileTreeManager.replacingDescendantURL(tab.url, from: old, to: new) {
                tab.url = r
            }
        }

        recentlyClosedURLs = recentlyClosedURLs.compactMap {
            fileTreeManager.replacingDescendantURL($0, from: old, to: new)
        }

        if let tab = selectedTab { syncPreviewContent(from: tab) }
    }

    func handleItemDeleted(at deletedURL: URL) {
        let deleted = deletedURL.standardizedFileURL

        let removed = openTabs.filter { fileTreeManager.isSameOrDescendant($0.url, of: deleted) }
        removed.forEach { endAccessing($0.url) }
        openTabs.removeAll { fileTreeManager.isSameOrDescendant($0.url, of: deleted) }
        recentlyClosedURLs.removeAll { fileTreeManager.isSameOrDescendant($0, of: deleted) }

        if let id = selectedFileID,
           fileTreeManager.isSameOrDescendant(id, of: deleted) { selectedFileID = nil }

        if let id = selectedTabID, !openTabs.contains(where: { $0.id == id }) {
            selectedTabID = openTabs.first?.id
        }

        if let tab = selectedTab {
            syncSidebarSelectionToTab(tab)
            syncPreviewContent(from: tab)
        } else {
            selectedTabID = nil
            clearPreview()
        }
    }

    // MARK: - External modification detection

    @ObservationIgnored private var knownModDates: [URL: Date] = [:]

    func recordModDate(for url: URL) {
        knownModDates[url] = fileService.attributes(at: url)?[.modificationDate] as? Date
    }

    func checkExternalModifications() {
        for tab in openTabs where !tab.isModified {
            let url = tab.url
            guard let attrs = fileService.attributes(at: url),
                  let diskDate = attrs[.modificationDate] as? Date else { continue }
            let known = knownModDates[url]
            if let known, diskDate > known {
                knownModDates[url] = diskDate
                externallyModifiedTab = tab
                showingReloadPrompt = true
                return
            } else if known == nil {
                knownModDates[url] = diskDate
            }
        }
    }

    func reloadExternallyModifiedTab() {
        guard let tab = externallyModifiedTab else { return }
        let url = tab.url
        let tabID = tab.id
        showingReloadPrompt = false
        externallyModifiedTab = nil
        Task.detached(priority: .userInitiated) { [weak self, service = fileService] in
            guard let content = try? service.readFile(at: url) else { return }
            await MainActor.run { [weak self] in
                guard let self,
                      let t = self.openTabs.first(where: { $0.id == tabID }) else { return }
                t.content = content
                t.isModified = false
                self.recordModDate(for: url)
                if self.selectedTabID == tabID { self.syncPreviewContent(from: t) }
            }
        }
    }

    func dismissReloadPrompt() {
        if let tab = externallyModifiedTab { recordModDate(for: tab.url) }
        showingReloadPrompt = false
        externallyModifiedTab = nil
    }

    // MARK: - Auto-save

    func setupAutoSaveTimer() {
        autoSaveTimer?.invalidate()
        autoSaveTimer = nil
        let settings = AppSettings.shared
        guard settings.autoSave else { return }
        autoSaveTimer = Timer.scheduledTimer(
            withTimeInterval: TimeInterval(settings.autoSaveInterval),
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in self?.autoSaveModifiedTabs() }
        }
        if autoSaveObserver == nil {
            autoSaveObserver = NotificationCenter.default.addObserver(
                forName: .autoSaveSettingsChanged, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.setupAutoSaveTimer() }
            }
        }
    }

    private func autoSaveModifiedTabs() {
        for tab in openTabs where tab.isModified { saveTab(tab) }
    }
}
