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

/// Central coordinator / thin facade.
///
/// Owns core cross-cutting state (rootURL, selectedFileID) and wires together
/// the five domain Managers. Views reference `state.openTabs`, `state.previewContent`
/// etc. through forwarding computed properties — all call sites are unchanged.
///
/// Managers:
///   TabManager      — tab lifecycle, file open/close, content mutation
///   FileTreeManager — sidebar tree, lazy-load, quick-open index
///   PreviewManager  — preview content, mode, scroll
///   ShareManager    — LAN share server
///   TemplateManager — template picker UI + CRUD
@MainActor
@Observable
final class AppState {

    // MARK: - Managers

    let tabManager: TabManager
    let fileTreeManager: FileTreeManager
    let previewManager: PreviewManager
    let shareManager: ShareManager
    let templateManager: TemplateManager

    // MARK: - Core shared state

    /// Project root (sandbox anchor). Shared by all managers.
    var rootURL: URL? {
        didSet {
            shareManager.sync(rootURL: rootURL, openTabs: tabManager.openTabs)
            if !isRestoringSession { scheduleSessionPersist() }
        }
    }

    /// Sidebar selection — separate from selectedTabID because a directory can be
    /// selected without opening a tab.
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
        let f = ByteCountFormatter(); f.countStyle = .file
        return f.string(fromByteCount: Int64(tab.content.utf8.count))
    }

    // MARK: - UI overlay

    var errorMessage: String?
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
        self.fileService     = fileService
        self.fileWatcher     = fileWatcher
        self.themeStore      = themeStore
        self.sessionStore    = sessionStore
        self.tabManager      = TabManager(fileService: fileService)
        self.fileTreeManager = FileTreeManager(fileService: fileService)
        self.previewManager  = PreviewManager()
        self.shareManager    = ShareManager()
        self.templateManager = TemplateManager()
        wireTabManagerCallbacks()
        setupAutoSaveTimer()
    }

    deinit {
        autoSaveTimer?.invalidate()
        if let autoSaveObserver {
            NotificationCenter.default.removeObserver(autoSaveObserver)
        }
        for url in accessRefCounts.keys { url.stopAccessingSecurityScopedResource() }
    }

    // MARK: - Wire TabManager callbacks

    private func wireTabManagerCallbacks() {
        tabManager.onOpenTabsChanged = { [weak self] in
            guard let self else { return }
            self.shareManager.sync(rootURL: self.rootURL, openTabs: self.tabManager.openTabs)
            if !self.isRestoringSession { self.scheduleSessionPersist() }
        }
        tabManager.onSelectedTabIDChanged = { [weak self] in
            guard let self, !self.isRestoringSession else { return }
            self.scheduleSessionPersist()
        }
        tabManager.onScheduleSessionPersist = { [weak self] in self?.scheduleSessionPersist() }
        tabManager.onSyncPreview            = { [weak self] tab in self?.previewManager.sync(from: tab) }
        tabManager.onClearPreview           = { [weak self] in self?.previewManager.clear() }
        tabManager.onSyncSidebarSelection   = { [weak self] tab in self?.syncSidebarSelectionToTab(tab) }
        tabManager.onSetSelectedFileID      = { [weak self] url in self?.selectedFileID = url }
        tabManager.onBeginAccessing         = { [weak self] url in self?.beginAccessing(url) }
        tabManager.onEndAccessing           = { [weak self] url in self?.endAccessing(url) }
        tabManager.onRequiresDirectFileAccess = { [weak self] url in self?.requiresDirectFileAccess(url) ?? true }
        tabManager.onRecordModDate          = { [weak self] url in self?.recordModDate(for: url) }
        tabManager.onReport                 = { [weak self] error in self?.report(error) }
    }

    // MARK: - TabManager forwarding

    var openTabs: [EditorTab] {
        get { tabManager.openTabs }
        set { tabManager.openTabs = newValue }
    }

    var selectedTabID: UUID? {
        get { tabManager.selectedTabID }
        set { tabManager.selectedTabID = newValue }
    }

    var selectedTab: EditorTab? {
        get { tabManager.selectedTab }
        set { tabManager.selectedTabID = newValue?.id }
    }

    var pendingCloseTab: EditorTab? {
        get { tabManager.pendingCloseTab }
        set { tabManager.pendingCloseTab = newValue }
    }
    var showingCloseConfirmation: Bool {
        get { tabManager.showingCloseConfirmation }
        set { tabManager.showingCloseConfirmation = newValue }
    }
    var pendingLargeFile: FileItem? {
        get { tabManager.pendingLargeFile }
        set { tabManager.pendingLargeFile = newValue }
    }
    var showingLargeFileWarning: Bool {
        get { tabManager.showingLargeFileWarning }
        set { tabManager.showingLargeFileWarning = newValue }
    }
    var recentlyClosedURLs: [URL] {
        get { tabManager.recentlyClosedURLs }
        set { tabManager.recentlyClosedURLs = newValue }
    }

    func openFile(_ item: FileItem)                { tabManager.openFile(item) }
    func openFileUnchecked(_ item: FileItem)       { tabManager.openFileUnchecked(item) }
    func applyLoadedContent(tabID: UUID, content: String) { tabManager.applyLoadedContent(tabID: tabID, content: content) }
    func failLoadingTab(tabID: UUID, url: URL, error: Error) { tabManager.failLoadingTab(tabID: tabID, url: url, error: error) }
    func closeTab(_ tabID: UUID)                   { tabManager.closeTab(tabID) }
    func confirmCloseTab(save: Bool)               { tabManager.confirmCloseTab(save: save) }
    func performCloseTab(_ tabID: UUID)            { tabManager.performCloseTab(tabID) }
    func updateTabContent(_ tabID: UUID, content: String) { tabManager.updateTabContent(tabID, content: content) }
    func saveTab(_ tab: EditorTab)                 { tabManager.saveTab(tab) }
    func saveCurrentTab()                          { tabManager.saveCurrentTab() }
    func selectTab(_ id: UUID)                     { tabManager.selectTab(id) }
    func reopenLastClosedTab()                     { tabManager.reopenLastClosedTab() }
    func selectNextTab()                           { tabManager.selectNextTab() }
    func selectPreviousTab()                       { tabManager.selectPreviousTab() }
    func moveTab(from src: Int, to dst: Int)       { tabManager.moveTab(from: src, to: dst) }

    // MARK: - FileTreeManager forwarding

    var fileTree: [FileItem]             { fileTreeManager.fileTree }
    var fileItemMap: [URL: FileItem]     { fileTreeManager.fileItemMap }
    var indexedFiles: [FileItem]         { fileTreeManager.indexedFiles }

    func reloadFileTree() {
        guard let rootURL else { return }
        fileTreeManager.reload(rootURL: rootURL)
    }

    func loadChildrenIfNeeded(for item: FileItem) { fileTreeManager.loadChildrenIfNeeded(for: item) }
    func isSameOrDescendant(_ url: URL, of base: URL) -> Bool { fileTreeManager.isSameOrDescendant(url, of: base) }
    func replacingDescendantURL(_ url: URL, from old: URL, to new: URL) -> URL? { fileTreeManager.replacingDescendantURL(url, from: old, to: new) }

    // MARK: - PreviewManager forwarding

    var previewContent: String             { previewManager.content }
    var previewContentRevision: Int        { previewManager.contentRevision }
    var previewLanguage: EditorLanguage    { previewManager.language }
    var previewMode: PreviewMode           { previewManager.mode }
    var previewHTMLFileURL: URL?           { previewManager.htmlFileURL }
    var previewReloadToken: Int            { previewManager.reloadToken }
    var previewExporter: PreviewExporter   { previewManager.exporter }
    var previewFindController: PreviewFindController { previewManager.findController }

    @discardableResult func clearPreview() -> Bool           { previewManager.clear() }
    @discardableResult func showMarkdownPreview(content: String) -> Bool { previewManager.showMarkdown(content: content) }
    @discardableResult func showHTMLPreview(fileURL: URL) -> Bool        { previewManager.showHTML(fileURL: fileURL) }
    func syncPreviewContent(from tab: EditorTab)             { previewManager.sync(from: tab) }

    // MARK: - ShareManager forwarding

    var shareServer: ShareManager { shareManager }
    func syncShareServerState() { shareManager.sync(rootURL: rootURL, openTabs: openTabs) }

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

    func updateCursorPosition(line: Int, column: Int) { cursorLine = line; cursorColumn = column }

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
        if let count = accessRefCounts[scoped] { accessRefCounts[scoped] = count + 1; return }
        if scoped.startAccessingSecurityScopedResource() { accessRefCounts[scoped] = 1 }
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

    // MARK: - Open folder

    func openFolder(_ url: URL) {
        let normalized = url.standardizedFileURL
        let previous   = rootURL?.standardizedFileURL
        if previous != normalized { beginAccessing(normalized) }

        rootURL = url
        if let previous, previous != normalized { endAccessing(previous) }

        tabManager.openTabs.forEach { endAccessing($0.url) }
        tabManager.openTabs.removeAll()
        tabManager.selectedTabID = nil
        selectedFileID = nil
        previewManager.clear()
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
            onSuccess: { [weak self] item in self?.reloadFileTree(); self?.openFile(item) },
            onError:   { [weak self] error in self?.report(error, logger: AppLog.file) }
        )
    }

    func saveCurrentAsTemplate(name: String) {
        guard let tab = selectedTab else { return }
        do    { try templateManager.saveAs(name: name, content: tab.content) }
        catch { setError(error.localizedDescription) }
    }

    // MARK: - Cross-domain coordination

    private func syncSidebarSelectionToTab(_ tab: EditorTab) {
        if fileTreeManager.fileItemMap[tab.url] != nil { selectedFileID = tab.url }
    }

    func handleItemRenamed(from oldURL: URL, to newURL: URL) {
        let old = oldURL.standardizedFileURL, new = newURL.standardizedFileURL

        if let id = selectedFileID,
           let r = fileTreeManager.replacingDescendantURL(id, from: old, to: new) {
            selectedFileID = r
        }
        for tab in tabManager.openTabs {
            if let r = fileTreeManager.replacingDescendantURL(tab.url, from: old, to: new) { tab.url = r }
        }
        tabManager.recentlyClosedURLs = tabManager.recentlyClosedURLs.compactMap {
            fileTreeManager.replacingDescendantURL($0, from: old, to: new)
        }
        if let tab = selectedTab { syncPreviewContent(from: tab) }
    }

    func handleItemDeleted(at deletedURL: URL) {
        let deleted = deletedURL.standardizedFileURL
        let removed = tabManager.openTabs.filter { fileTreeManager.isSameOrDescendant($0.url, of: deleted) }
        removed.forEach { endAccessing($0.url) }
        tabManager.openTabs.removeAll { fileTreeManager.isSameOrDescendant($0.url, of: deleted) }
        tabManager.recentlyClosedURLs.removeAll { fileTreeManager.isSameOrDescendant($0, of: deleted) }

        if let id = selectedFileID,
           fileTreeManager.isSameOrDescendant(id, of: deleted) { selectedFileID = nil }

        if let id = tabManager.selectedTabID,
           !tabManager.openTabs.contains(where: { $0.id == id }) {
            tabManager.selectedTabID = tabManager.openTabs.first?.id
        }

        if let tab = selectedTab { syncSidebarSelectionToTab(tab); syncPreviewContent(from: tab) }
        else                     { tabManager.selectedTabID = nil; previewManager.clear() }
    }

    // MARK: - External modification detection

    @ObservationIgnored private var knownModDates: [URL: Date] = [:]

    func recordModDate(for url: URL) {
        knownModDates[url] = fileService.attributes(at: url)?[.modificationDate] as? Date
    }

    func checkExternalModifications() {
        for tab in tabManager.openTabs where !tab.isModified {
            let url = tab.url
            guard let attrs = fileService.attributes(at: url),
                  let diskDate = attrs[.modificationDate] as? Date else { continue }
            let known = knownModDates[url]
            if let known, diskDate > known {
                knownModDates[url] = diskDate
                externallyModifiedTab = tab
                showingReloadPrompt = true
                return
            } else if known == nil { knownModDates[url] = diskDate }
        }
    }

    func reloadExternallyModifiedTab() {
        guard let tab = externallyModifiedTab else { return }
        let url = tab.url, tabID = tab.id
        showingReloadPrompt = false; externallyModifiedTab = nil
        Task.detached(priority: .userInitiated) { [weak self, svc = fileService] in
            guard let content = try? svc.readFile(at: url) else { return }
            await MainActor.run { [weak self] in
                guard let self,
                      let t = self.tabManager.openTabs.first(where: { $0.id == tabID }) else { return }
                t.content = content; t.isModified = false
                self.recordModDate(for: url)
                if self.tabManager.selectedTabID == tabID { self.syncPreviewContent(from: t) }
            }
        }
    }

    func dismissReloadPrompt() {
        if let tab = externallyModifiedTab { recordModDate(for: tab.url) }
        showingReloadPrompt = false; externallyModifiedTab = nil
    }

    // MARK: - Session (inlined from AppState+Session.swift)

    private var sessionSnapshot: (urls: [URL], selectedIndex: Int?) {
        let urls = tabManager.openTabs.map(\.url)
        let selectedIdx = tabManager.selectedTabID.flatMap { id in
            tabManager.openTabs.firstIndex(where: { $0.id == id })
        }
        return (urls, selectedIdx)
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

        var seenURLs = Set(tabManager.openTabs.map(\.url.standardizedFileURL))
        var restored: [(tab: EditorTab, url: URL)] = []
        var restoredSelectedID: UUID?

        for (i, bookmark) in session.tabs.enumerated() {
            guard let resolved = SessionStore.resolveBookmark(bookmark) else { continue }
            let url = resolved.url
            guard fileService.fileExists(at: url), !url.hasDirectoryPath,
                  !seenURLs.contains(url.standardizedFileURL) else { continue }
            if requiresDirectFileAccess(url) { beginAccessing(url) }
            let lang = FileTypeConfiguration.shared.editorLanguage(for: url.pathExtension.lowercased()) ?? .markdown
            let tab  = EditorTab(url: url, content: "", language: lang, awaitingInitialContent: true)
            seenURLs.insert(url.standardizedFileURL)
            if session.selectedTabIndex == i { restoredSelectedID = tab.id }
            restored.append((tab, url))
        }

        tabManager.openTabs.append(contentsOf: restored.map(\.tab))

        if tabManager.selectedTabID == nil,
           let restoredSelectedID,
           let tab = tabManager.openTabs.first(where: { $0.id == restoredSelectedID }) {
            tabManager.selectedTabID = tab.id
            syncSidebarSelectionToTab(tab)
            syncPreviewContent(from: tab)
        }

        for (tab, url) in restored {
            let tabID = tab.id
            let svc   = fileService
            Task.detached(priority: .userInitiated) { [weak self] in
                do    { let content = try svc.readFile(at: url); await self?.applyLoadedContent(tabID: tabID, content: content) }
                catch { await self?.failLoadingTab(tabID: tabID, url: url, error: error) }
            }
        }
    }

    // MARK: - Auto-save

    func setupAutoSaveTimer() {
        autoSaveTimer?.invalidate(); autoSaveTimer = nil
        let settings = AppSettings.shared
        guard settings.autoSave else { return }
        autoSaveTimer = Timer.scheduledTimer(
            withTimeInterval: TimeInterval(settings.autoSaveInterval), repeats: true
        ) { [weak self] _ in Task { @MainActor in self?.autoSaveModifiedTabs() } }
        if autoSaveObserver == nil {
            autoSaveObserver = NotificationCenter.default.addObserver(
                forName: .autoSaveSettingsChanged, object: nil, queue: .main
            ) { [weak self] _ in Task { @MainActor in self?.setupAutoSaveTimer() } }
        }
    }

    private func autoSaveModifiedTabs() {
        for tab in tabManager.openTabs where tab.isModified { saveTab(tab) }
    }
}
