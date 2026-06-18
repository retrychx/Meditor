import Foundation
import Observation

extension Notification.Name {
    static let autoSaveSettingsChanged = Notification.Name("MEditor.autoSaveSettingsChanged")
    static let previewFontSizeChanged = Notification.Name("MEditor.previewFontSizeChanged")
    static let editorFontSizeChanged = Notification.Name("MEditor.editorFontSizeChanged")
    static let docPathChanged = Notification.Name("MEditor.docPathChanged")
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
        static let gitlabHost = "MEditor.gitlabHost"
        static let gitlabVisibility = "MEditor.gitlabVisibility"
        static let aiAccentStyle = "MEditor.aiAccentStyle"
        static let aiProvider = "MEditor.aiProvider"
        static let aiBaseURL = "MEditor.aiBaseURL"
        static let aiModel = "MEditor.aiModel"
        static let aiCLIPath = "MEditor.aiCLIPath"
        static let userDocPathBookmark = "MEditor.userDocPathBookmark"
        static let appDocPathBookmark  = "MEditor.appDocPathBookmark"
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

    /// GitLab host for Snippet sharing (e.g. gitlab.example.com). Empty = unset.
    var gitlabHost: String {
        didSet { defaults.set(gitlabHost, forKey: Key.gitlabHost) }
    }

    /// Default snippet visibility: "internal" or "private".
    var gitlabVisibility: String {
        didSet { defaults.set(gitlabVisibility, forKey: Key.gitlabVisibility) }
    }

    /// AI assistant accent style: "system" (app accent) or "shadcn" (mono black/white).
    var aiAccentStyle: String {
        didSet { defaults.set(aiAccentStyle, forKey: Key.aiAccentStyle) }
    }

    /// AI provider mode: "disabled" | "openai" | "claudeCLI".
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
        gitlabHost = d.string(forKey: Key.gitlabHost) ?? ""
        gitlabVisibility = d.string(forKey: Key.gitlabVisibility) ?? "internal"
        aiAccentStyle = d.string(forKey: Key.aiAccentStyle) ?? "system"
        aiProvider = d.string(forKey: Key.aiProvider) ?? "disabled"
        aiBaseURL = d.string(forKey: Key.aiBaseURL) ?? "https://api.openai.com/v1"
        aiModel = d.string(forKey: Key.aiModel) ?? "gpt-4o-mini"
        aiCLIPath = d.string(forKey: Key.aiCLIPath) ?? "/usr/local/bin/claude"
    }
}
