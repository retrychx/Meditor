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
        didSet { if !isRestoringSession { persistSession() } }
    }
    var openTabs: [EditorTab] = [] {
        didSet { if !isRestoringSession { persistSession() } }
    }
    var selectedTabID: UUID? {
        didSet { if !isRestoringSession { persistSession() } }
    }
    var previewContent: String = ""
    var previewLanguage: EditorLanguage = .markdown
    var previewMode: PreviewMode = .empty
    var previewHTMLFileURL: URL?
    var previewReloadToken: Int = 0
    var errorMessage: String?

    // MARK: - Cursor / Status

    var cursorLine: Int = 1
    var cursorColumn: Int = 1
    var editorVisibleLine: Int = 0
    var previewVisibleLine: Int = 0

    func updateCursorPosition(line: Int, column: Int) {
        cursorLine = line
        cursorColumn = column
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
        if let count = accessRefCounts[url] {
            accessRefCounts[url] = count + 1
            return
        }
        if url.startAccessingSecurityScopedResource() {
            accessRefCounts[url] = 1
        }
    }

    func endAccessing(_ url: URL) {
        guard let count = accessRefCounts[url] else { return }
        if count > 1 {
            accessRefCounts[url] = count - 1
            return
        }
        accessRefCounts.removeValue(forKey: url)
        url.stopAccessingSecurityScopedResource()
    }

    deinit {
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
    let fileWatcher = FileWatcherService()
    let themeStore: PreviewThemeStore
    let previewExporter = PreviewExporter()
    let sessionStore: SessionStore
    let shareServer = LocalShareServer()

    init(fileService: FileServiceProtocol = FileService(),
         themeStore: PreviewThemeStore = PreviewThemeStore(),
         sessionStore: SessionStore = SessionStore()) {
        self.fileService = fileService
        self.themeStore = themeStore
        self.sessionStore = sessionStore
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
        rootURL = url
        openTabs.forEach { endAccessing($0.url) }
        openTabs.removeAll()
        selectedTabID = nil
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
