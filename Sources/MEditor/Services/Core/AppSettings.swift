import Foundation
import Observation

extension Notification.Name {
    static let autoSaveSettingsChanged    = Notification.Name("MEditor.autoSaveSettingsChanged")
    static let previewFontSizeChanged     = Notification.Name("MEditor.previewFontSizeChanged")
    static let editorFontSizeChanged      = Notification.Name("MEditor.editorFontSizeChanged")
    static let docPathChanged             = Notification.Name("MEditor.docPathChanged")
    static let claudeMonitorSettingsChanged = Notification.Name("MEditor.claudeMonitorSettingsChanged")
}

/// Centralized app preferences, persisted via UserDefaults.
@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard
    private enum Key {
        static let sharePort = "MEditor.sharePort"
        static let previewFontSize = "MEditor.previewFontSize"
        static let editorFontSize = "MEditor.editorFontSize"
        static let editorFontName = "MEditor.editorFontName"
        static let showEditorOnLaunch = "MEditor.showEditorOnLaunch"
        static let showPreviewOnLaunch = "MEditor.showPreviewOnLaunch"
        static let showSidebarOnLaunch = "MEditor.showSidebarOnLaunch"
        static let autoSave = "MEditor.autoSave"
        static let autoSaveInterval = "MEditor.autoSaveInterval"
        static let githubGistPublic = "MEditor.githubGistPublic"
        static let shareBaseURL = "MEditor.shareBaseURL"
        static let aiAccentStyle = "MEditor.aiAccentStyle"
        static let aiProvider = "MEditor.aiProvider"
        static let aiBaseURL = "MEditor.aiBaseURL"
        static let aiModel = "MEditor.aiModel"
        static let aiCLIPath = "MEditor.aiCLIPath"
        static let aiCLIModel    = "MEditor.aiCLIModel"
        static let aiAgentModel     = "MEditor.aiAgentModel"
        static let aiAgentMaxSteps    = "MEditor.aiAgentMaxSteps"
        static let aiRequestTimeout   = "MEditor.aiRequestTimeout"
        static let aiInlineModel      = "MEditor.aiInlineModel"
        static let aiCustomSystemPrompt = "MEditor.aiCustomSystemPrompt"
        static let aiAutoAttachContext  = "MEditor.aiAutoAttachContext"
        static let userDocPathBookmark = "MEditor.userDocPathBookmark"
        static let appDocPathBookmark  = "MEditor.appDocPathBookmark"
        // Claude Code 监听
        static let claudeMonitorEnabled   = "MEditor.claudeMonitorEnabled"
        static let claudeMonitorCustomPath = "MEditor.claudeMonitorCustomPath"
        static let claudeMonitorFileExts  = "MEditor.claudeMonitorFileExts"
        // 导出
        static let exportPreflightEnabled = "MEditor.exportPreflightEnabled"
        static let pdfPaperSize  = "MEditor.pdfPaperSize"
        static let pdfMargins    = "MEditor.pdfMargins"
        static let pdfShowHeader = "MEditor.pdfShowHeader"
        static let pdfShowFooter = "MEditor.pdfShowFooter"
        static let pdfCoverPage  = "MEditor.pdfCoverPage"
    }

    /// LAN share server port (default 8899).
    var sharePort: UInt16 {
        didSet { defaults.set(Int(sharePort), forKey: Key.sharePort) }
    }

    /// Preview font size in px (default 15).
    var previewFontSize: Int {
        didSet {
            defaults.set(previewFontSize, forKey: Key.previewFontSize)
            NotificationCenter.default.post(name: .previewFontSizeChanged, object: nil)
        }
    }

    /// Editor font size in pt (default 14).
    var editorFontSize: Int {
        didSet {
            defaults.set(editorFontSize, forKey: Key.editorFontSize)
            NotificationCenter.default.post(name: .editorFontSizeChanged, object: nil)
        }
    }

    /// 编辑器正文字体（EditorFont.rawValue，默认 system）。与字号共用同一变更通知。
    var editorFontName: String {
        didSet {
            defaults.set(editorFontName, forKey: Key.editorFontName)
            NotificationCenter.default.post(name: .editorFontSizeChanged, object: nil)
        }
    }

    /// Show editor panel on launch.
    var showEditorOnLaunch: Bool {
        didSet { defaults.set(showEditorOnLaunch, forKey: Key.showEditorOnLaunch) }
    }

    /// Show preview panel on launch.
    var showPreviewOnLaunch: Bool {
        didSet { defaults.set(showPreviewOnLaunch, forKey: Key.showPreviewOnLaunch) }
    }

    /// Show sidebar on launch.
    var showSidebarOnLaunch: Bool {
        didSet { defaults.set(showSidebarOnLaunch, forKey: Key.showSidebarOnLaunch) }
    }

    /// Enable auto-save.
    var autoSave: Bool {
        didSet {
            defaults.set(autoSave, forKey: Key.autoSave)
            NotificationCenter.default.post(name: .autoSaveSettingsChanged, object: nil)
        }
    }

    /// Auto-save interval in seconds (default 30).
    var autoSaveInterval: Int {
        didSet {
            defaults.set(autoSaveInterval, forKey: Key.autoSaveInterval)
            NotificationCenter.default.post(name: .autoSaveSettingsChanged, object: nil)
        }
    }

    /// Whether new GitHub Gists are created as public (true) or secret (false).
    var githubGistPublic: Bool {
        didSet { defaults.set(githubGistPublic, forKey: Key.githubGistPublic) }
    }

    /// 在线分享服务的 Base URL（默认 workers.dev；发布前换成自定义域名，只改这一处）。
    var shareBaseURL: String {
        didSet { defaults.set(shareBaseURL, forKey: Key.shareBaseURL) }
    }

    /// AI assistant accent style: "system" (app accent) or "shadcn" (mono black/white).
    var aiAccentStyle: String {
        didSet { defaults.set(aiAccentStyle, forKey: Key.aiAccentStyle) }
    }

    /// AI provider mode: "disabled" | "openai" | "anthropic" | "claudeCLI".
    var aiProvider: String {
        didSet { defaults.set(aiProvider, forKey: Key.aiProvider) }
    }

    /// OpenAI-compatible base URL (e.g. https://api.openai.com/v1, http://localhost:11434/v1).
    var aiBaseURL: String {
        didSet { defaults.set(aiBaseURL, forKey: Key.aiBaseURL) }
    }

    /// Model name (e.g. gpt-4o-mini, llama3.1, qwen2.5).
    var aiModel: String {
        didSet { defaults.set(aiModel, forKey: Key.aiModel) }
    }

    /// Absolute path to the local `claude` CLI binary.
    var aiCLIPath: String {
        didSet { defaults.set(aiCLIPath, forKey: Key.aiCLIPath) }
    }

    /// Claude CLI 使用的模型（空则使用 CLI 默认）。e.g. "claude-opus-4-5"
    var aiCLIModel: String {
        didSet { defaults.set(aiCLIModel, forKey: Key.aiCLIModel) }
    }

    /// Agent 工具调用专用模型（空则回退到 aiModel）。
    var aiAgentModel: String {
        didSet { defaults.set(aiAgentModel, forKey: Key.aiAgentModel) }
    }

    /// Agent 最大执行步数（默认 30）。
    var aiAgentMaxSteps: Int {
        didSet { defaults.set(aiAgentMaxSteps, forKey: Key.aiAgentMaxSteps) }
    }

    /// 单次 HTTP 请求超时（秒）。默认 300s，适配推理模型长思考。
    var aiRequestTimeout: TimeInterval {
        didSet { defaults.set(aiRequestTimeout, forKey: Key.aiRequestTimeout) }
    }

    /// 内联编辑（改写/扩写/精简/翻译）专用模型（空则回退到 aiModel）。
    var aiInlineModel: String {
        didSet { defaults.set(aiInlineModel, forKey: Key.aiInlineModel) }
    }

    /// 用户自定义系统提示词：追加到 AI 助手/Agent 的系统提示词末尾（空则不注入）。
    var aiCustomSystemPrompt: String {
        didSet { defaults.set(aiCustomSystemPrompt, forKey: Key.aiCustomSystemPrompt) }
    }

    /// 发送聊天时自动把当前激活 tab 的文档作为默认上下文注入（默认开）。
    /// 输入栏 chip 可针对单次发送移除；此开关为全局总开关。
    var aiAutoAttachContext: Bool {
        didSet { defaults.set(aiAutoAttachContext, forKey: Key.aiAutoAttachContext) }
    }

    // MARK: - Claude Code 监听

    /// 是否启用 Claude Code 会话文件监听功能。
    var claudeMonitorEnabled: Bool {
        didSet {
            defaults.set(claudeMonitorEnabled, forKey: Key.claudeMonitorEnabled)
            NotificationCenter.default.post(name: .claudeMonitorSettingsChanged, object: nil)
        }
    }

    /// 自定义监听目录路径（空则使用默认的 ~/.claude/projects/）。
    var claudeMonitorCustomPath: String {
        didSet {
            defaults.set(claudeMonitorCustomPath, forKey: Key.claudeMonitorCustomPath)
            NotificationCenter.default.post(name: .claudeMonitorSettingsChanged, object: nil)
        }
    }

    /// 要监听的文件扩展名，逗号分隔（默认 "md,txt")。
    var claudeMonitorFileExts: String {
        didSet {
            defaults.set(claudeMonitorFileExts, forKey: Key.claudeMonitorFileExts)
            NotificationCenter.default.post(name: .claudeMonitorSettingsChanged, object: nil)
        }
    }

    // MARK: - 导出

    /// 导出 PDF/HTML 前是否先跑文档诊断（死链/缺图/标题/代码块）。
    var exportPreflightEnabled: Bool {
        didSet { defaults.set(exportPreflightEnabled, forKey: Key.exportPreflightEnabled) }
    }

    /// PDF 纸张大小（PDFExportOptions.PaperSize.rawValue，默认 a4）。
    var pdfPaperSize: String {
        didSet { defaults.set(pdfPaperSize, forKey: Key.pdfPaperSize) }
    }

    /// PDF 页边距档位（PDFExportOptions.MarginPreset.rawValue，默认 normal）。
    var pdfMargins: String {
        didSet { defaults.set(pdfMargins, forKey: Key.pdfMargins) }
    }

    /// PDF 页眉（文档标题）。
    var pdfShowHeader: Bool {
        didSet { defaults.set(pdfShowHeader, forKey: Key.pdfShowHeader) }
    }

    /// PDF 页脚（页码）。
    var pdfShowFooter: Bool {
        didSet { defaults.set(pdfShowFooter, forKey: Key.pdfShowFooter) }
    }

    /// PDF 封面页（标题 + 日期）。
    var pdfCoverPage: Bool {
        didSet { defaults.set(pdfCoverPage, forKey: Key.pdfCoverPage) }
    }

    /// 当前持久化值聚合成的 PDF 导出选项（非法 rawValue 回退默认）。
    var pdfExportOptions: PDFExportOptions {
        PDFExportOptions(
            paperSize: PDFExportOptions.PaperSize(rawValue: pdfPaperSize) ?? .a4,
            margins: PDFExportOptions.MarginPreset(rawValue: pdfMargins) ?? .normal,
            showHeader: pdfShowHeader,
            showFooter: pdfShowFooter,
            coverPage: pdfCoverPage
        )
    }

    /// 解析 `claudeMonitorFileExts` 为扩展名数组（小写无点）。
    var claudeMonitorExtensions: [String] {
        claudeMonitorFileExts
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
            .filter { !$0.isEmpty }
    }

    /// 实际监听目录：自定义路径优先，空则回退到默认 ~/.claude/projects/。
    var claudeMonitorDirectory: URL {
        let custom = claudeMonitorCustomPath.trimmingCharacters(in: .whitespaces)
        if !custom.isEmpty {
            return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath)
        }
        return URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".claude/projects", isDirectory: true)
    }

    // MARK: - Document paths

    /// User's preferred document directory (security-scoped bookmark).
    var userDocPath: URL? {
        get { resolveBookmark(forKey: Key.userDocPathBookmark) }
    }

    func setUserDocPath(_ url: URL?) throws {
        if let url {
            let data = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            defaults.set(data, forKey: Key.userDocPathBookmark)
        } else {
            defaults.removeObject(forKey: Key.userDocPathBookmark)
        }
        NotificationCenter.default.post(name: .docPathChanged, object: nil)
    }

    /// App document output directory (default: Application Support/MEditor/Documents).
    var appDocPath: URL {
        get {
            if let url = resolveBookmark(forKey: Key.appDocPathBookmark) { return url }
            return defaultAppDocPath
        }
    }

    func setAppDocPath(_ url: URL?) throws {
        if let url {
            let data = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            defaults.set(data, forKey: Key.appDocPathBookmark)
        } else {
            defaults.removeObject(forKey: Key.appDocPathBookmark)
        }
        NotificationCenter.default.post(name: .docPathChanged, object: nil)
    }

    // MARK: - Theme token overrides

    /// Returns the user's saved override for a CSS token in a given theme, or nil if using the default.
    func themeToken(_ token: String, forTheme themeId: String) -> String? {
        defaults.string(forKey: "MEditor.themeToken.\(themeId).\(token)")
    }

    /// Saves (or clears, when value is nil) the user's override for a CSS token in a given theme.
    func setThemeToken(_ value: String?, token: String, forTheme themeId: String) {
        let key = "MEditor.themeToken.\(themeId).\(token)"
        if let value { defaults.set(value, forKey: key) }
        else { defaults.removeObject(forKey: key) }
    }

    var defaultAppDocPath: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("MEditor/Documents", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func resolveBookmark(forKey key: String) -> URL? {
        guard let data = defaults.data(forKey: key) else { return nil }
        var isStale = false
        return try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }

    private init() {
        let d = UserDefaults.standard
        sharePort = UInt16(d.integer(forKey: Key.sharePort) != 0 ? d.integer(forKey: Key.sharePort) : 8899)
        previewFontSize = d.integer(forKey: Key.previewFontSize) != 0 ? d.integer(forKey: Key.previewFontSize) : 15
        editorFontSize = d.integer(forKey: Key.editorFontSize) != 0 ? d.integer(forKey: Key.editorFontSize) : 14
        editorFontName = d.string(forKey: Key.editorFontName) ?? EditorFont.system.rawValue
        showEditorOnLaunch = d.object(forKey: Key.showEditorOnLaunch) != nil ? d.bool(forKey: Key.showEditorOnLaunch) : false
        showPreviewOnLaunch = d.object(forKey: Key.showPreviewOnLaunch) != nil ? d.bool(forKey: Key.showPreviewOnLaunch) : true
        showSidebarOnLaunch = d.object(forKey: Key.showSidebarOnLaunch) != nil ? d.bool(forKey: Key.showSidebarOnLaunch) : true
        autoSave = d.bool(forKey: Key.autoSave)
        autoSaveInterval = d.integer(forKey: Key.autoSaveInterval) != 0 ? d.integer(forKey: Key.autoSaveInterval) : 30
        githubGistPublic = d.bool(forKey: Key.githubGistPublic)  // default false = secret
        shareBaseURL = d.string(forKey: Key.shareBaseURL) ?? "https://meditor-app.863129776.workers.dev"
        aiAccentStyle = d.string(forKey: Key.aiAccentStyle) ?? "system"
        aiProvider = d.string(forKey: Key.aiProvider) ?? "disabled"
        aiBaseURL = d.string(forKey: Key.aiBaseURL) ?? "https://api.openai.com/v1"
        // 迁移：DeepSeek 旧模型已下线，映射到 v4 系列。
        let rawAIModel = d.string(forKey: Key.aiModel) ?? "gpt-4o-mini"
        aiModel = rawAIModel == "deepseek-chat" ? "deepseek-v4-flash"
                : rawAIModel == "deepseek-reasoner" ? "deepseek-v4-pro"
                : rawAIModel
        aiCLIPath    = d.string(forKey: Key.aiCLIPath)    ?? "/usr/local/bin/claude"
        aiCLIModel   = d.string(forKey: Key.aiCLIModel)   ?? ""
        aiAgentModel    = d.string(forKey: Key.aiAgentModel) ?? ""
        let rawMaxSteps = d.integer(forKey: Key.aiAgentMaxSteps)
        aiAgentMaxSteps = (rawMaxSteps >= 5 && rawMaxSteps <= 100) ? rawMaxSteps : 30
        let rawTimeout  = d.double(forKey: Key.aiRequestTimeout)
        aiRequestTimeout = rawTimeout >= 30 ? rawTimeout : 300   // 默认 300s
        aiInlineModel = d.string(forKey: Key.aiInlineModel) ?? ""
        aiCustomSystemPrompt = d.string(forKey: Key.aiCustomSystemPrompt) ?? ""
        aiAutoAttachContext = d.object(forKey: Key.aiAutoAttachContext) != nil
            ? d.bool(forKey: Key.aiAutoAttachContext) : true
        // Claude Code 监听
        claudeMonitorEnabled    = d.object(forKey: Key.claudeMonitorEnabled) != nil ? d.bool(forKey: Key.claudeMonitorEnabled) : false
        claudeMonitorCustomPath = d.string(forKey: Key.claudeMonitorCustomPath) ?? ""
        claudeMonitorFileExts   = d.string(forKey: Key.claudeMonitorFileExts) ?? "md,txt"
        // 导出
        exportPreflightEnabled = d.object(forKey: Key.exportPreflightEnabled) != nil ? d.bool(forKey: Key.exportPreflightEnabled) : true
        pdfPaperSize  = d.string(forKey: Key.pdfPaperSize) ?? PDFExportOptions.PaperSize.a4.rawValue
        pdfMargins    = d.string(forKey: Key.pdfMargins) ?? PDFExportOptions.MarginPreset.normal.rawValue
        pdfShowHeader = d.object(forKey: Key.pdfShowHeader) != nil ? d.bool(forKey: Key.pdfShowHeader) : false
        pdfShowFooter = d.object(forKey: Key.pdfShowFooter) != nil ? d.bool(forKey: Key.pdfShowFooter) : false
        pdfCoverPage  = d.bool(forKey: Key.pdfCoverPage)   // default false
    }
}

/// 编辑器正文字体候选，持久化存 rawValue（见 AppSettings.editorFontName）。
/// 菜单显示名直接用字体本名（不本地化），system 的文案在设置页取 L("settings.editorFont.system")。
enum EditorFont: String, CaseIterable {
    case system           // 系统默认（SF，对 CJK 渲染最稳）
    case sfMono = "SF Mono"
    case menlo = "Menlo"
    case newYork = "New York"
    case pingFang = "PingFang SC"

    var displayName: String { rawValue }
}
