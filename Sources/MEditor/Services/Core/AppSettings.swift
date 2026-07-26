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
        static let userDocPathBookmark = "MEditor.userDocPathBookmark"
        static let appDocPathBookmark  = "MEditor.appDocPathBookmark"
        // Claude Code 监听
        static let claudeMonitorEnabled   = "MEditor.claudeMonitorEnabled"
        static let claudeMonitorCustomPath = "MEditor.claudeMonitorCustomPath"
        static let claudeMonitorFileExts  = "MEditor.claudeMonitorFileExts"
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
        // Claude Code 监听
        claudeMonitorEnabled    = d.object(forKey: Key.claudeMonitorEnabled) != nil ? d.bool(forKey: Key.claudeMonitorEnabled) : false
        claudeMonitorCustomPath = d.string(forKey: Key.claudeMonitorCustomPath) ?? ""
        claudeMonitorFileExts   = d.string(forKey: Key.claudeMonitorFileExts) ?? "md,txt"
    }
}
