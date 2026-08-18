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
    let shareLinkPublisher: ShareLinkPublisher
    let templateManager: TemplateManager
    let pluginManager: PluginManager
    let presentationManager: PresentationManager

    /// 工作区 Git 状态（侧边栏文件树 M/A/? 标记）；非 git 工作区静默为空。
    let gitStatusService = GitStatusService()

    /// Agent 命令审批缓存（App 会话级）：safe 命令批准一次，整个会话内
    /// 不再逐轮弹框——缓存从 per-context（每轮消息新建即失效）提升到共享实例。
    let commandApprovals = CommandApprovalStore()

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
            // 工作区切换 → 重建内容索引；关闭（nil）→ 释放
            if rootURL?.standardizedFileURL != oldValue?.standardizedFileURL {
                rebuildWorkspaceIndex(root: rootURL)
                if rootURL == nil { gitStatusService.clear() }
            }
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
    var editorWriteBackContent: String { aiUI.editorWriteBackContent }
    var editorWriteBackNonce: Int { aiUI.editorWriteBackNonce }
    var pendingReplaceRange: NSRange? {
        get { aiUI.pendingReplaceRange }
        set { aiUI.pendingReplaceRange = newValue }
    }

    /// AI 写回的统一入口：编辑器挂载且目标是当前 tab 时走编辑器可撤销写回
    /// （最小化替换，保留滚动位置/光标/undo 链）；否则退回整体替换路径
    /// （预览独占等场景，updateTabContent 内部已处理预览同步与防抖保存）。
    func applyAIWriteBack(_ tabID: UUID, content: String) {
        if tabID == selectedTab?.id, isEditorMounted {
            aiUI.requestWriteBack(content)
        } else {
            updateTabContent(tabID, content: content)
        }
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

    var previewSelectedRect: CGRect {
        get { aiUI.previewSelectedRect }
        set { aiUI.previewSelectedRect = newValue }
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
                showingGlobalSearch = false
                // Lazily build the file index only when QuickOpen is actually opened.
                if let root = rootURL { fileTreeManager.ensureIndexReady(rootURL: root) }
            }
        }
    }
    /// 全局搜索面板（⌘⇧F）：基于 workspaceIndex 的内容搜索浮层。
    var showingGlobalSearch = false {
        didSet { if showingGlobalSearch { showingQuickOpen = false } }
    }
    var showingSettings = false
    /// 请求设置页打开时定位到的 tab（首启引导的「配置 AI 服务」深链到 AI tab）；
    /// 一次性消费，SettingsHeroOverlay 展示后清零。
    var settingsRequestedTab: SettingsView.SettingsTab? = nil
    /// SettingsHeroOverlay 遮罩/面板展开的真实动画状态（与 showingSettings 不同：
    /// 后者立即置位驱动 overlay 的挂载/卸载，这个值才是 spring 动画实际驱动的
    /// 那个开合状态）。EditorTabBar 的 tab 条暗化需要跟这个值同步，不能读
    /// showingSettings，否则两处动画时序错位。
    var settingsOverlayShown = false
    var showingCloseProjectConfirmation = false
    var showingAIAssistant: Bool {
        get { aiUI.showingAssistant }
        set { aiUI.showingAssistant = newValue }
    }
    var showingBeautifySheet = false {
        didSet { if showingBeautifySheet { showingQuickOpen = false } }
    }
    /// 文档诊断面板（工具菜单）：本地规则引擎扫描工作区死链/缺图/标题问题。
    var showingDiagnostics = false {
        didSet {
            if showingDiagnostics {
                showingQuickOpen = false
                showingGlobalSearch = false
            }
        }
    }
    var showingInlineEdit = false

    // MARK: - Services

    let fileService: FileServiceProtocol
    let fileWatcher: any FileWatcherServiceProtocol
    let themeStore: PreviewThemeStore
    let sessionStore: SessionStore
    let filePickerService: FilePickerServiceProtocol

    // MARK: - 工作区内容索引（全局搜索 UI 与 Agent search_workspace 共用）

    let workspaceIndex = WorkspaceIndexService()

    /// 首启引导的一键演示流程（临时目录写示例文档 + 自动发 Agent 指令）
    let agentDemoFlow = AgentDemoFlow()
    /// 首次全量构建完成标记（@Observable 可追踪），搜索 UI 用它显示「索引构建中…」。
    private(set) var workspaceIndexReady = false

    /// rootURL 变化时重建/释放索引；构建在 actor 后台执行，不占主线程。
    private func rebuildWorkspaceIndex(root: URL?) {
        workspaceIndexReady = false
        let index = workspaceIndex
        guard let root else {
            Task { await index.clear() }
            return
        }
        Task {
            await index.buildIndex(root: root)
            workspaceIndexReady = true
        }
    }

    /// FSEvents 变化后的索引增量刷新（服务内部防抖；首次构建未完成时由 buildIndex 全量兜底）。
    func scheduleWorkspaceIndexRefresh(root: URL) {
        let index = workspaceIndex
        Task { await index.scheduleRefresh(root: root) }
    }

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
        // 发布在线链接的 HTML 取自预览 webview（PreviewExporter 持有弱引用）
        let exporter = self.previewManager.exporter
        self.shareLinkPublisher = ShareLinkPublisher(webViewProvider: { [weak exporter] in exporter?.webView })
        self.templateManager = TemplateManager()
        self.pluginManager   = PluginManager()
        self.presentationManager = PresentationManager()
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
            Task { @MainActor [weak self] in self?.restartClaudeMonitorIfNeeded() }
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
        tabManager.onDidWriteToDisk          = { [weak self] url in
            self?.previewManager.reloadHTML(url: url)
            // 保存落盘后即时刷新内容索引（FSEvents diff 路径之外的就地快路径）
            guard let self else { return }
            let index = self.workspaceIndex
            Task { await index.updateFile(at: url) }
        }
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

    func requestEditorScroll(to line: Int, select: Bool = false) {
        guard line >= 0 else { return }
        editorScrollCommand = editorScrollCommand.advanced(to: line, select: select)
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

    // MARK: - Presentation Mode

    /// 是否正在演讲模式放映中。
    var isPresenting: Bool { presentationManager.isPresenting }

    /// 放映期间的主题跟踪是否已注册（withObservationTracking 单次触发，防止重复挂链）。
    @ObservationIgnored private var isObservingPresentationTheme = false

    /// 以当前选中的 Markdown 文档进入演讲模式（无选中或非 Markdown 时无操作）。
    func startPresentation() {
        guard let tab = selectedTab, tab.language == .markdown else { return }
        presentationManager.start(markdown: tab.content, sourceURL: tab.url, theme: themeStore.current)
        // 放映期间跟踪预览主题切换，实时同步到放映页
        if presentationManager.isPresenting {
            observePresentationThemeChanges()
        }
    }

    /// 把当前 Markdown 文档导出为单文件自包含的演讲 HTML（无选中或非 Markdown 时无操作）。
    func exportPresentation() {
        guard let tab = selectedTab, tab.language == .markdown else { return }
        let slides = SlideSplitter.split(tab.content)
        // file:// 形式的 <base href>，使导出的 HTML 在浏览器中能加载相对路径图片
        let baseHref = tab.url.deletingLastPathComponent().absoluteString
        guard let html = PresentationExporter.makeHTML(slides: slides, theme: themeStore.current, baseHref: baseHref) else {
            showToast("演讲模式资源缺失，无法导出", icon: "exclamationmark.triangle")
            return
        }

        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        savePanel.title = "Export Presentation"
        savePanel.nameFieldStringValue = tab.url.deletingPathExtension().lastPathComponent + "-slides.html"
        savePanel.allowedContentTypes = [.html]
        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }
            do {
                try html.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                self.setError(error.localizedDescription)
            }
        }
    }

    /// 放映期间用 withObservationTracking 跟踪预览主题并转发给放映窗口。
    /// 该跟踪单次触发，因此每次变化后需要续订，直到放映结束。
    private func observePresentationThemeChanges() {
        guard !isObservingPresentationTheme else { return }
        isObservingPresentationTheme = true
        withObservationTracking {
            _ = themeStore.current
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isObservingPresentationTheme = false
                guard self.presentationManager.isPresenting else { return }
                self.presentationManager.applyTheme(self.themeStore.current)
                self.observePresentationThemeChanges()
            }
        }
    }
}
