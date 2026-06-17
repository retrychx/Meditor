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
/// Owns cross-cutting state (rootURL, selectedFileID) and wires together
/// five domain Managers. Forwarding API is split into extension files:
///
///   AppState+Tabs.swift        → Tab lifecycle forwarding
///   AppState+FileTree.swift    → File tree, CRUD, open-folder, coordination
///   AppState+Preview.swift     → Preview forwarding
///   AppState+Session.swift     → Session persistence
///   AppState+ExternalMod.swift → External file-change detection + auto-save
@MainActor
@Observable
final class AppState {

    // MARK: - Managers

    let tabManager: TabManager
    let fileTreeManager: FileTreeManager
    let previewManager: PreviewManager
    let shareManager: ShareManager
    let gitlabShareManager: GitLabShareManager
    let templateManager: TemplateManager

    /// AI assistant conversation store (multi-session, persisted).
    let aiConversation = AIConversation()

    // MARK: - Core shared state

    var rootURL: URL? {
        didSet {
            shareManager.sync(rootURL: rootURL, openTabs: tabManager.openTabs)
            if !isRestoringSession { scheduleSessionPersist() }
        }
    }

    var selectedFileID: URL?

    // MARK: - Cursor / Status bar

    var cursorLine: Int = 1
    var cursorColumn: Int = 1
    var editorVisibleLine: Int = 0
    var previewVisibleLine: Int = 0
    var editorScrollCommand: ScrollSyncCommand = .idle
    var previewScrollCommand: ScrollSyncCommand = .idle

    /// Current editor selection (empty when nothing selected). Used as AI context.
    var editorSelectedText: String = ""
    /// AI → editor insert command (text + monotonic nonce).
    var editorInsertText: String = ""
    var editorInsertNonce: Int = 0

    func insertIntoEditor(_ text: String) {
        editorInsertText = text
        editorInsertNonce += 1
    }

    var currentFileSize: String {
        guard let tab = selectedTab else { return "" }
        let f = ByteCountFormatter(); f.countStyle = .file
        return f.string(fromByteCount: Int64(tab.content.utf8.count))
    }

    // MARK: - UI overlay

    var errorMessage: String?
    var showingQuickOpen = false
    var showingSettings = false
    var showingAIAssistant = false
    var externallyModifiedTab: EditorTab?
    var showingReloadPrompt = false

    // MARK: - Services

    let fileService: FileServiceProtocol
    let fileWatcher: any FileWatcherServiceProtocol
    let themeStore: PreviewThemeStore
    let sessionStore: SessionStore

    // MARK: - Internal bookkeeping

    @ObservationIgnored private(set) var accessRefCounts: [URL: Int] = [:]
    @ObservationIgnored var isRestoringSession = false
    @ObservationIgnored private var sessionPersistScheduled = false
    @ObservationIgnored var autoSaveTimer: Timer?
    @ObservationIgnored var autoSaveObserver: Any?
    /// Mod-dates for open files; used by AppState+ExternalMod.
    @ObservationIgnored var externalModDates: [URL: Date] = [:]

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
        self.gitlabShareManager = GitLabShareManager()
        self.templateManager = TemplateManager()
        wireTabManagerCallbacks()
        setupAutoSaveTimer()
    }

    deinit {
        autoSaveTimer?.invalidate()
        if let obs = autoSaveObserver { NotificationCenter.default.removeObserver(obs) }
        for url in accessRefCounts.keys { url.stopAccessingSecurityScopedResource() }
    }

    // MARK: - TabManager callback wiring

    private func wireTabManagerCallbacks() {
        tabManager.onOpenTabsChanged = { [weak self] in
            guard let self else { return }
            self.shareManager.sync(rootURL: self.rootURL, openTabs: self.tabManager.openTabs)
            if !self.isRestoringSession { self.scheduleSessionPersist() }
        }
        tabManager.onSelectedTabIDChanged    = { [weak self] in
            guard let self, !self.isRestoringSession else { return }
            self.scheduleSessionPersist()
        }
        tabManager.onScheduleSessionPersist  = { [weak self] in self?.scheduleSessionPersist() }
        tabManager.onSyncPreview             = { [weak self] tab in self?.previewManager.sync(from: tab) }
        tabManager.onClearPreview            = { [weak self] in self?.previewManager.clear() }
        tabManager.onSyncSidebarSelection    = { [weak self] tab in self?.syncSidebarSelectionToTab(tab) }
        tabManager.onSetSelectedFileID       = { [weak self] url in self?.selectedFileID = url }
        tabManager.onBeginAccessing          = { [weak self] url in self?.beginAccessing(url) }
        tabManager.onEndAccessing            = { [weak self] url in self?.endAccessing(url) }
        tabManager.onRequiresDirectFileAccess = { [weak self] url in self?.requiresDirectFileAccess(url) ?? true }
        tabManager.onRecordModDate           = { [weak self] url in self?.recordModDate(for: url) }
        tabManager.onReport                  = { [weak self] err in self?.report(err) }
    }

    // MARK: - Shared helpers (used by multiple extensions)

    func scheduleSessionPersist() {
        guard !sessionPersistScheduled else { return }
        sessionPersistScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.sessionPersistScheduled = false
            self.persistSession()
        }
    }

    func setError(_ message: String) { errorMessage = message }

    func report(_ error: AppError, logger: Logger = AppLog.app) {
        AppLog.error(error, in: logger)
        if error.severity == .user { errorMessage = error.errorDescription }
    }

    func beginAccessing(_ url: URL) {
        let s = url.standardizedFileURL
        if let c = accessRefCounts[s] { accessRefCounts[s] = c + 1; return }
        if s.startAccessingSecurityScopedResource() { accessRefCounts[s] = 1 }
    }

    func endAccessing(_ url: URL) {
        let s = url.standardizedFileURL
        guard let c = accessRefCounts[s] else { return }
        if c > 1 { accessRefCounts[s] = c - 1; return }
        accessRefCounts.removeValue(forKey: s)
        s.stopAccessingSecurityScopedResource()
    }

    func requiresDirectFileAccess(_ url: URL) -> Bool {
        guard let rootURL else { return true }
        return !fileTreeManager.isSameOrDescendant(url, of: rootURL)
    }

    func updateCursorPosition(line: Int, column: Int) { cursorLine = line; cursorColumn = column }

    func requestEditorScroll(to line: Int) {
        guard line >= 0 else { return }
        editorScrollCommand = editorScrollCommand.advanced(to: line)
    }

    func requestPreviewScroll(to line: Int) {
        guard line >= 0 else { return }
        previewScrollCommand = previewScrollCommand.advanced(to: line)
    }

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

    func createFromTemplate(_ template: DocumentTemplate) {
        templateManager.createFromTemplate(
            template, rootURL: rootURL, fileService: fileService,
            onSuccess: { [weak self] item in self?.reloadFileTree(); self?.openFile(item) },
            onError:   { [weak self] err  in self?.report(err, logger: AppLog.file) }
        )
    }

    func saveCurrentAsTemplate(name: String) {
        guard let tab = selectedTab else { return }
        do    { try templateManager.saveAs(name: name, content: tab.content) }
        catch { setError(error.localizedDescription) }
    }
}
