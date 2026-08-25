import AppIntents
import AppKit
import Foundation

// MARK: - Intent 错误

enum MEditorIntentError: Error, LocalizedError {
    case emptyText
    case noWorkspace
    case noActiveDocument
    case fileNotFound
    case appStateUnavailable

    var errorDescription: String? {
        switch self {
        case .emptyText:           return "The text to append is empty."
        case .noWorkspace:         return "No MEditor workspace found. Open a folder in MEditor first."
        case .noActiveDocument:    return "No Markdown document is currently selected in MEditor."
        case .fileNotFound:        return "The specified path does not exist."
        case .appStateUnavailable: return "MEditor did not finish launching in time."
        }
    }
}

// MARK: - 共享辅助

@MainActor
private enum IntentAppBridge {
    /// 正在运行的 app 的 AppState（经 NSApplicationDelegateAdaptor 注入）。
    static func currentAppState() -> AppState? {
        (NSApp.delegate as? MEditorAppDelegate)?.appState
    }

    /// 冷启动竞态：intent perform 可能先于窗口 onAppear（AppState 注入点）执行，
    /// 轮询等待注入完成。openAppWhenRun 的 intent 会拉起前台窗口，注入必然发生。
    static func waitForAppState(timeoutNanoseconds: UInt64 = 10_000_000_000) async -> AppState? {
        if let state = currentAppState() { return state }
        var waited: UInt64 = 0
        let step: UInt64 = 250_000_000
        while waited < timeoutNanoseconds {
            try? await Task.sleep(nanoseconds: step)
            waited += step
            if let state = currentAppState() { return state }
        }
        return nil
    }

    /// 从持久化会话解析最近一次打开的工作区（app 未运行时 AppState 不可用的兜底路径）。
    static func lastSessionRoot() -> URL? {
        guard let session = SessionStore().load(),
              let data = session.rootBookmark,
              let resolved = SessionStore.resolveBookmark(data),
              FileManager.default.fileExists(atPath: resolved.url.path) else { return nil }
        return resolved.url
    }
}

// MARK: - 追加文本到收件箱（inbox.md）

struct AppendToInboxIntent: AppIntent {
    static let title: LocalizedStringResource = "Add to MEditor Inbox"
    static let description = IntentDescription(
        "Appends a Markdown todo item to inbox.md in the current MEditor workspace.")
    static let openAppWhenRun = false

    @Parameter(title: "Text", description: "The todo text to append.")
    var text: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MEditorIntentError.emptyText }

        // 优先走运行中的 AppState：编辑器里打开着 inbox.md 时同步内容
        if let appState = IntentAppBridge.currentAppState(), let root = appState.rootURL {
            let inbox = root.appendingPathComponent("inbox.md")
            let content = try await appState.todoStore.addTodo(text: trimmed, to: inbox)
            if let tab = appState.openTabs.first(where: {
                $0.url.standardizedFileURL == inbox.standardizedFileURL
            }) {
                if tab.isModified {
                    // 编辑区有未保存改动：把新条目合并进内存内容，
                    // 不能用磁盘内容覆盖（会静默丢掉未保存编辑）
                    tab.content += "\n- [ ] \(trimmed)"
                } else {
                    tab.content = content
                }
                tab.contentRevision &+= 1
            }
            return .result(dialog: "Added to inbox.md")
        }

        // 兜底：app 未在前台运行时，写入最近会话工作区的 inbox.md
        guard let root = IntentAppBridge.lastSessionRoot() else {
            throw MEditorIntentError.noWorkspace
        }
        let inbox = root.appendingPathComponent("inbox.md")
        _ = try await TodoStore().addTodo(text: trimmed, to: inbox)
        return .result(dialog: "Added to inbox.md")
    }
}

// MARK: - 打开指定文档/工作区

struct OpenDocumentIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Document in MEditor"
    static let description = IntentDescription(
        "Opens a Markdown document in MEditor (or a folder as the workspace).")
    static let openAppWhenRun = true

    @Parameter(title: "Path", description: "Absolute POSIX path of the document or folder to open.")
    var path: String

    @MainActor
    func perform() async throws -> some IntentResult {
        let url = URL(fileURLWithPath: path.trimmingCharacters(in: .whitespacesAndNewlines))
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else {
            throw MEditorIntentError.fileNotFound
        }
        guard await IntentAppBridge.waitForAppState() != nil else {
            throw MEditorIntentError.appStateUnavailable
        }
        if isDir.boolValue {
            // 目录：直接作为工作区打开
            (NSApp.delegate as? MEditorAppDelegate)?.appState?.openFolder(url)
        } else {
            // 文件：与 Spotlight 点击共用同一条打开路由（工作区内打开 / 散文件 / 新开父目录）
            (NSApp.delegate as? MEditorAppDelegate)?.openOrEnqueue(url)
        }
        return .result()
    }
}

// MARK: - 导出当前文档为 PDF

struct ExportCurrentDocumentPDFIntent: AppIntent {
    static let title: LocalizedStringResource = "Export Current Document as PDF"
    static let description = IntentDescription(
        "Exports the document currently selected in MEditor as a PDF (with export options and save panel).")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let appState = await IntentAppBridge.waitForAppState() else {
            throw MEditorIntentError.appStateUnavailable
        }
        guard let tab = appState.selectedTab, tab.language == .markdown else {
            throw MEditorIntentError.noActiveDocument
        }
        // 走应用内统一的导出流程（预检 → PDF 选项 → 保存面板）
        appState.requestExport(.pdf)
        return .result()
    }
}

// MARK: - App Shortcuts 注册

struct MEditorAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AppendToInboxIntent(),
            phrases: [
                "Add to \(.applicationName) inbox",
                "Add note to \(.applicationName) inbox"
            ],
            shortTitle: "Add to Inbox",
            systemImageName: "tray.and.arrow.down"
        )
        AppShortcut(
            intent: OpenDocumentIntent(),
            phrases: [
                "Open document in \(.applicationName)"
            ],
            shortTitle: "Open Document",
            systemImageName: "doc.text"
        )
        AppShortcut(
            intent: ExportCurrentDocumentPDFIntent(),
            phrases: [
                "Export current document as PDF with \(.applicationName)"
            ],
            shortTitle: "Export PDF",
            systemImageName: "doc.richtext"
        )
    }
}
