import Foundation
import Observation
import OSLog
import SwiftUI

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
    let githubGistManager: GitHubGistManager
    let templateManager: TemplateManager
    let pluginManager: PluginManager

    /// AI assistant conversation store (multi-session, persisted).
    /// Lazy so disk I/O is deferred until the AI panel is first opened.
    @ObservationIgnored
    private(set) lazy var aiConversation: AIConversation = AIConversation()

    /// 全局待办状态，两个 Todo 视图共享同一份数据。
    let todoStore = TodoStore()

    // MARK: - Core shared state

    var rootURL: URL? {
        didSet {
            shareManager.sync(rootURL: rootURL, openTabs: tabManager.openTabs)
            if !isRestoringSession { scheduleSessionPersist() }
        }
    }

    var selectedFileID: URL?

    // MARK: - AI UI State

    let aiUI = AIUIState()

    // MARK: - Diff Review State

    let diffReview = DiffReviewState()
    /// 多一层直接属性，避免嵌套 @Observable 被 SwiftUI 漏追踪的问题
    var showingDiffReview: Bool {
        get { diffReview.isPresented }
        set { diffReview.isPresented = newValue }
    }
    /// 每次 mentionItems 更新时递增，供 AtMentionPickerView .task(id:) 追踪变化
    var mentionItemsVersion: Int = 0

    /// @mention 搜索用的文件+目录全量列表。
    /// 作为 AppState 的真正存储属性（非 computed 转发），确保 @Observable 能追踪变化，
    /// 由 fileTreeManager.onMentionItemsUpdated 回调同步。
    var mentionItems: [FileItem] = []

    // MARK: - Cursor / Status bar

    var cursorLine: Int = 1
    var cursorColumn: Int = 1
    /// 最近一次保存成功的时间，用于状态栏短暂显示"已保存"提示。
    var lastSavedAt: Date? = nil
    /// NativeEditorView 出现时置 true，消失时置 false。
    /// 用于 insertIntoEditor 判断走光标插入路径还是追加路径。
    var isEditorMounted: Bool = false
    var editorVisibleLine: Int = 0
    var previewVisibleLine: Int = 0
    var editorScrollCommand: ScrollSyncCommand = .idle
    var previewScrollCommand: ScrollSyncCommand = .idle

    // MARK: - Editor selection tracking (NSRange, updated by EditorCoordinator)
    var editorSelectedRange: NSRange = NSRange(location: 0, length: 0)

    // Computed wrappers keep View layer unchanged while delegating to AIUIState.
    var editorSelectedText: String {
        get { aiUI.editorSelectedText }
        set { aiUI.editorSelectedText = newValue }
    }
    var editorInsertText: String { aiUI.editorInsertText }
    var editorInsertNonce: Int { aiUI.editorInsertNonce }

    var editorReplaceText: String { aiUI.editorReplaceText }
    var editorReplaceNonce: Int { aiUI.editorReplaceNonce }
    var pendingReplaceRange: NSRange? {
        get { aiUI.pendingReplaceRange }
        set { aiUI.pendingReplaceRange = newValue }
    }

    func insertIntoEditor(_ text: String) {
        guard let tab = selectedTab else { return }

        if isEditorMounted {
            // 编辑器可见：走 nonce 路径，在光标处插入（保留光标位置）
            aiUI.requestInsert(text)
        } else {
            // 编辑器隐藏（纯预览 / AI 模式）：直接追加到 tab.content
            if tab.language == .html {
                // HTML 文件：插入到 </body> 之前，保持结构合法
                let bodyClose = "</body>"
                if let range = tab.content.range(of: bodyClose, options: .caseInsensitive) {
                    tab.content.replaceSubrange(range, with: "\n" + text + "\n" + bodyClose)
                } else {
                    tab.content += "\n" + text
                }
            } else {
                // Markdown 及其他文本：追加到末尾
                let separator = tab.content.isEmpty ? "" : "\n\n"
                tab.content += separator + text
            }
            tab.contentRevision &+= 1   // 触发编辑器（如果稍后显示）刷新内容
            scheduleDebounceSave()
        }
    }

    func replaceInEditor(_ text: String) {
        aiUI.requestReplace(text)
    }

    var previewSelectedText: String {
        get { aiUI.previewSelectedText }
        set { aiUI.previewSelectedText = newValue }
    }

    @discardableResult
    func replaceInMarkdownSource(original: String, replacement: String) -> Bool {
        guard let tab = selectedTab else { return false }
        let content = tab.content

        // 找到所有出现位置
        var ranges: [Range<String.Index>] = []
        var searchStart = content.startIndex
        while let found = content.range(of: original, range: searchStart..<content.endIndex) {
            ranges.append(found)
            searchStart = found.upperBound
            // 超过 2 个就没必要继续找了
            if ranges.count > 1 { break }
        }

        guard !ranges.isEmpty else { return false }

        if ranges.count > 1 {
            // 文本在文档中出现多次，无法精确定位，提示用户手动处理
            let msg = L("ai.error.replaceAmbiguous")
            setError(msg)
            return false
        }

        tab.content.replaceSubrange(ranges[0], with: replacement)
        // AI 内联改写后触发自动保存
        scheduleDebounceSave()
        return true
    }

    var currentFileSize: String {
        guard let tab = selectedTab else { return "" }
        let f = ByteCountFormatter(); f.countStyle = .file
        return f.string(fromByteCount: Int64(tab.content.utf8.count))
    }

    // MARK: - UI overlay

    var errorMessage: String?
    var toastMessage: ToastMessage?

    /// 打开 AI 面板，并把选中文本作为「引用选段」带入（显示为输入框上方的引用卡片）。
    func openAssistantWithSelection(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        aiUI.quotedContext = t.isEmpty ? nil : t
        aiUI.showingAssistant = true
    }

    func showToast(_ text: String, icon: String? = nil) {
        withAnimation(DS.Motion.fast) {
            toastMessage = ToastMessage(text, icon: icon)
        }
    }

    var showingQuickOpen = false {
        didSet {
            if showingQuickOpen {
                showingBeautifySheet = false
                // Lazily build the file index only when QuickOpen is actually opened.
                if let root = rootURL { fileTreeManager.ensureIndexReady(rootURL: root) }
            }
        }
    }
    var showingSettings = false
    var showingCloseProjectConfirmation = false
    var showingAIAssistant: Bool {
        get { aiUI.showingAssistant }
        set { aiUI.showingAssistant = newValue }
    }
    var externallyModifiedTab: EditorTab?
    var showingReloadPrompt = false
    var showingBeautifySheet = false {
        didSet { if showingBeautifySheet { showingQuickOpen = false } }
    }
    var showingInlineEdit = false

    // MARK: - Services

    let fileService: FileServiceProtocol
    let fileWatcher: any FileWatcherServiceProtocol
    let themeStore: PreviewThemeStore
    let sessionStore: SessionStore
    let filePickerService: FilePickerServiceProtocol

    // MARK: - 散文件 & Claude 监听

    let looseFiles = LooseFilesStore()

    /// Claude 创建文件时弹出的提示（有按钮的 Toast）
    var claudeFilePrompt: ClaudeFilePrompt? = nil

    @ObservationIgnored private let claudeMonitor = ClaudeSessionMonitor()
    @ObservationIgnored private var claudeMonitorObserver: Any?

    // MARK: - Internal bookkeeping

    @ObservationIgnored private(set) var accessRefCounts: [URL: Int] = [:]
    @ObservationIgnored var isRestoringSession = false
    @ObservationIgnored private var sessionPersistScheduled = false
    @ObservationIgnored var autoSaveTimer: Timer?
    @ObservationIgnored var autoSaveObserver: Any?
    /// 输入停止后 2 秒触发保存的防抖计时器。
    @ObservationIgnored var debounceSaveTimer: Timer?
    /// Mod-dates for open files; used by AppState+ExternalMod.
    @ObservationIgnored var externalModDates: [URL: Date] = [:]

    // MARK: - Init

    init(
        fileService: FileServiceProtocol = FileService(),
        fileWatcher: any FileWatcherServiceProtocol = FileWatcherService(),
        themeStore: PreviewThemeStore = PreviewThemeStore(),
        sessionStore: SessionStore = SessionStore(),
        filePicker: FilePickerServiceProtocol? = nil
    ) {
        self.fileService     = fileService
        self.fileWatcher     = fileWatcher
        self.themeStore      = themeStore
        self.sessionStore    = sessionStore
        self.filePickerService = filePicker ?? MacFilePickerService()
        self.tabManager      = TabManager(fileService: fileService)
        self.fileTreeManager = FileTreeManager(fileService: fileService)
        self.previewManager  = PreviewManager()
        self.shareManager    = ShareManager()
        self.githubGistManager = GitHubGistManager()
        self.templateManager = TemplateManager()
        self.pluginManager   = PluginManager()
        wireTabManagerCallbacks()
        setupAutoSaveTimer()
        pluginManager.load()
        setupClaudeMonitor()
        fileTreeManager.onMentionItemsUpdated = { [weak self] in
            guard let self else { return }
            self.mentionItems = self.fileTreeManager.mentionItems
            self.mentionItemsVersion &+= 1
        }
    }

    deinit {
        autoSaveTimer?.invalidate()
        debounceSaveTimer?.invalidate()
        if let obs = autoSaveObserver { NotificationCenter.default.removeObserver(obs) }
        for url in accessRefCounts.keys { url.stopAccessingSecurityScopedResource() }
    }

    // MARK: - Claude 监听配置

    private func setupClaudeMonitor() {
        // 注册事件回调（无论开关状态如何均只注册一次）
        claudeMonitor.onFileCreated = { [weak self] event in
            guard let self else { return }
            self.handleClaudeFileCreated(event)
        }

        // 仅开启时启动
        let settings = AppSettings.shared
        if settings.claudeMonitorEnabled {
            claudeMonitor.start(
                directory: settings.claudeMonitorDirectory,
                extensions: settings.claudeMonitorExtensions
            )
        }

        // 设置变更时重启监听（只注册一次，存储 token 防止重复注册）
        claudeMonitorObserver = NotificationCenter.default.addObserver(
            forName: .claudeMonitorSettingsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.restartClaudeMonitorIfNeeded()
        }
    }

    private func restartClaudeMonitorIfNeeded() {
        let settings = AppSettings.shared
        claudeMonitor.stop()
        if settings.claudeMonitorEnabled {
            claudeMonitor.start(
                directory: settings.claudeMonitorDirectory,
                extensions: settings.claudeMonitorExtensions
            )
        }
    }

    private func handleClaudeFileCreated(_ event: ClaudeFileEvent) {
        // 如果文件已经在散文件列表，不重复提示
        guard !looseFiles.contains(event.fileURL) else { return }
        withAnimation(DS.Motion.fast) {
            claudeFilePrompt = ClaudeFilePrompt(
                fileURL: event.fileURL,
                onAccept: { [weak self] in
                    guard let self else { return }
                    self.claudeFilePrompt = nil
                    self.looseFiles.add(event.fileURL, source: .claude)
                    self.openLooseFile(event.fileURL)
                },
                onDismiss: { [weak self] in
                    self?.claudeFilePrompt = nil
                }
            )
        }
    }

    /// 打开一个散文件（Tab 已打开则跳转，否则新建 Tab）。
    func openLooseFile(_ url: URL) {
        // 如果已有 Tab 则跳转
        if let existing = openTabs.first(where: { $0.url == url }) {
            selectedTabID = existing.id
            return
        }
        let item = FileItem(url: url, isDirectory: false)
        openFile(item)
        // 确保在散文件列表中有记录
        looseFiles.add(url, source: .manual)
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
        tabManager.onDidSave                 = { [weak self] in self?.lastSavedAt = Date() }
        tabManager.onDidWriteToDisk          = { [weak self] url in self?.previewManager.reloadHTML(url: url) }
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

    // MARK: - Todo helpers

    /// 将一条新待办写入当前编辑文件末尾（md）；无打开文件时写入 rootURL/inbox.md。
    /// 磁盘写入在后台执行，完成后同步编辑器内容。
    func appendTodoToCurrentFile(_ text: String) {
        let targetURL: URL
        if let tab = selectedTab, tab.url.pathExtension.lowercased() == "md" {
            targetURL = tab.url
        } else if let root = rootURL {
            targetURL = root.appendingPathComponent("inbox.md")
        } else {
            showToast("请先打开一个工作区", icon: "exclamationmark.triangle")
            return
        }
        Task {
            do {
                let newContent = try await todoStore.addTodo(text: text, to: targetURL)
                // 同步编辑器
                if let tab = selectedTab, tab.url == targetURL {
                    tab.content = newContent
                    tab.contentRevision &+= 1
                }
                showToast("已新增待办到 \(targetURL.lastPathComponent)", icon: "checkmark.circle")
            } catch {
                setError(error.localizedDescription)
            }
        }
    }
}
