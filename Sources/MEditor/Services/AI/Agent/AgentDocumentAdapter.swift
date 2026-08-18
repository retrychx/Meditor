import Foundation

// MARK: - Protocol

/// AppState 交互的抽象 — 封装所有对 Tab / 编辑器 / 文件树 / Toast 的操作。
/// 工具不直接感知此协议；AgentContext 把它与 AgentFileRepository 组合后暴露 AgentContextProtocol。
@MainActor
protocol AgentDocumentAdapter: AnyObject {
    var currentDocument: String?     { get }
    var currentDocumentName: String? { get }
    var workspaceURL: URL?           { get }
    var currentTabURL: URL?          { get }   // 供 resolveFile 优先级排序用

    // 当前文档（Tab）操作
    func writeDocument(_ content: String) throws
    func patchDocument(find: String, replace: String, all: Bool) throws -> Int
    func insertIntoDocument(_ text: String)

    // Tab 查询 & 操作
    func contentForTab(at url: URL) -> String?  // 返回 nil 表示未打开或尚未加载
    func openFile(at url: URL) -> Bool
    /// 是否有已打开的 Tab 对应此文件（写入 confinement 的散文件例外）
    func hasOpenTab(at url: URL) -> Bool

    // 文件操作完成后的通知（由 AgentContext 在磁盘 IO 后回调）
    func notifyFileCreated(_ url: URL)
    func notifyFileWritten(_ url: URL, content: String, isNew: Bool)
    func notifyDirectoryCreated(_ url: URL)

    // 命令授权
    func confirmCommandExecution(_ command: String, cwd: String?) async -> Bool
    /// 取消挂起的命令确认（Runner 超时/正常结束时触发），恢复工具内挂起的 continuation。
    func cancelPendingCommandConfirmation()

    // 文件写入授权（与命令确认同一范式）
    /// 向用户展示确认条，询问是否允许 agent 写入/修改该文件。
    func confirmFileWrite(_ path: String, summary: String) async -> Bool
    /// 携带 diff 预览的写入确认（协议要求，保证 existential 动态分发；
    /// 默认实现转发旧签名，见下方 extension）。
    func confirmFileWrite(_ preview: FileWritePreview) async -> Bool
    /// 取消挂起的文件写入确认（Runner 超时/正常结束时触发），语义与
    /// cancelPendingCommandConfirmation 完全对齐。
    func cancelPendingWriteConfirmation()
    /// 本次 agent run 的「全部允许」开关（确认条点过「本次运行全部允许」后为 true）。
    var isFileWriteAllowedForRun: Bool { get }
}

extension AgentDocumentAdapter {
    /// 默认无打开 Tab——mock / 测试实现无需关心此方法。
    func hasOpenTab(at url: URL) -> Bool { false }
    /// 默认无挂起确认——mock / 测试实现无需关心此方法。
    func cancelPendingCommandConfirmation() {}
    /// 默认放行——mock / headless 实现无需感知写入确认流程，不破坏既有 conformer。
    func confirmFileWrite(_ path: String, summary: String) async -> Bool { true }
    /// 默认丢弃 diff、转发旧签名——只实现 path/summary 版本的 conformer 语义不变。
    func confirmFileWrite(_ preview: FileWritePreview) async -> Bool {
        await confirmFileWrite(preview.path, summary: preview.summary)
    }
    /// 默认无挂起确认——与 cancelPendingCommandConfirmation 的默认实现同理。
    func cancelPendingWriteConfirmation() {}
    /// 默认无「全部允许」状态——未接入 UI 的实现每次写都走 confirmFileWrite（其默认实现放行）。
    var isFileWriteAllowedForRun: Bool { false }
}

// MARK: - AppState Implementation

@MainActor
final class AppStateDocumentAdapter: AgentDocumentAdapter {

    weak var appState: AppState?

    /// 用于 patchDocument / currentDocument 在 Tab 尚未加载时的读盘 fallback
    let fileRepo: any AgentFileRepository

    init(appState: AppState, fileRepo: any AgentFileRepository) {
        self.appState = appState
        self.fileRepo = fileRepo
    }

    // MARK: - State

    var currentDocument: String? {
        guard let tab = appState?.selectedTab else { return nil }
        // Tab 刚打开，内容异步加载中：回退读盘，避免 agent 误判"文件为空"
        if tab.awaitingInitialContent {
            return (try? fileRepo.readFileSyncFallback(at: tab.url)) ?? tab.content
        }
        return tab.content
    }

    var currentDocumentName: String? { appState?.selectedTab?.name }
    var workspaceURL: URL?           { appState?.rootURL }
    var currentTabURL: URL?          { appState?.selectedTab?.url.standardizedFileURL }

    // MARK: - Document ops

    func writeDocument(_ content: String) throws {
        guard let state = appState,
              let tab = state.selectedTab else { throw AgentContextError.noActiveDocument }
        state.updateTabContent(tab.id, content: content)
    }

    func patchDocument(find: String, replace: String, all: Bool = false) throws -> Int {
        guard let state = appState,
              let tab = state.selectedTab else { throw AgentContextError.noActiveDocument }
        let original = tab.awaitingInitialContent
            ? ((try? fileRepo.readFileSyncFallback(at: tab.url)) ?? tab.content)
            : tab.content
        let (updated, count) = PatchEngine.apply(to: original, find: find, replace: replace, all: all)
        if count == 0 {
            throw PatchNotFoundError(
                find: find,
                nearbyContext: PatchEngine.nearbyContext(in: original, around: find)
            )
        }
        state.updateTabContent(tab.id, content: updated)
        return count
    }

    func insertIntoDocument(_ text: String) {
        appState?.insertIntoEditor(text)
    }

    // MARK: - Tab

    func contentForTab(at url: URL) -> String? {
        appState?.openTabs.first {
            $0.url.standardizedFileURL == url.standardizedFileURL && !$0.awaitingInitialContent
        }?.content
    }

    func hasOpenTab(at url: URL) -> Bool {
        appState?.openTabs.contains {
            $0.url.standardizedFileURL == url.standardizedFileURL
        } ?? false
    }

    func openFile(at url: URL) -> Bool {
        guard let state = appState,
              FileManager.default.fileExists(atPath: url.path) else { return false }
        state.openFile(FileItem(url: url, isDirectory: false))
        return true
    }

    // MARK: - Notifications

    func notifyFileCreated(_ url: URL) {
        guard let state = appState else { return }
        state.reloadFileTree()
        // 已在 @MainActor，无需 DispatchQueue.main.async
        state.openFile(FileItem(url: url, isDirectory: false))
        state.showToast("已创建 \(url.lastPathComponent)", icon: "doc.badge.plus")
    }

    func notifyFileWritten(_ url: URL, content: String, isNew: Bool) {
        guard let state = appState else { return }
        state.reloadFileTree()
        // 刷新已打开的同名 Tab
        if let tab = state.openTabs.first(where: {
            $0.url.standardizedFileURL == url.standardizedFileURL
        }) {
            state.updateTabContent(tab.id, content: content)
            tab.isModified = false
        }
        state.reloadHTMLPreviewIfShowing(url)
        let filename = url.lastPathComponent
        if isNew {
            // 已在 @MainActor，无需 DispatchQueue.main.async
            state.openFile(FileItem(url: url, isDirectory: false))
            state.showToast("已创建 \(filename)", icon: "doc.badge.plus")
        } else {
            state.showToast("已更新 \(filename)", icon: "checkmark.circle")
        }
    }

    func notifyDirectoryCreated(_ url: URL) {
        guard let state = appState else { return }
        state.reloadFileTree()
        let displayName: String
        if let root = state.rootURL?.path, url.path.hasPrefix(root) {
            displayName = String(url.path.dropFirst(root.count + 1))
        } else {
            displayName = url.lastPathComponent
        }
        state.showToast("已创建目录 \(displayName)", icon: "folder.badge.plus")
    }

    // MARK: - Command confirmation

    func confirmCommandExecution(_ command: String, cwd: String?) async -> Bool {
        guard let convo = appState?.aiConversation else { return false }
        // 注意：不在此处做会话级缓存判断。
        // 缓存策略（per-command-key）由 RunCommandTool 通过 AgentContext 管理，
        // 此方法仅负责 UI 层展示确认对话框。
        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            convo.pendingCommand = PendingCommand(command: command, cwd: cwd) { approved in
                convo.pendingCommand = nil
                cont.resume(returning: approved)
            }
        }
    }

    /// Runner 超时/正常结束时拒绝挂起的命令确认，恢复工具内 withCheckedContinuation。
    /// PendingCommand.reject 幂等（answered 标记），与 AIConversation.cancelStreaming 的
    /// 补救路径不冲突（先到先生效，后到的是 no-op）。
    func cancelPendingCommandConfirmation() {
        guard let convo = appState?.aiConversation else { return }
        convo.pendingCommand?.reject()
        convo.pendingCommand = nil
    }

    // MARK: - File write confirmation

    /// 「本次运行全部允许」开关。作用域 = 本 adapter 实例：
    /// macOS 每次 run 由 AIChatCoordinator 经 AgentContext.make 新建 adapter，
    /// 因此实例级标志天然是 run 级——新 run 自动重置，无需 Runner 显式清零。
    /// 不做 per-path 缓存的理由见 PendingWrite.approveAll 注释。
    private var fileWriteAllowedForRun = false
    var isFileWriteAllowedForRun: Bool { fileWriteAllowedForRun }

    /// 旧签名入口：无 diff 数据，按「写前内容不可得」构造 preview 转发。
    func confirmFileWrite(_ path: String, summary: String) async -> Bool {
        await confirmFileWrite(FileWritePreview(path: path, summary: summary, diff: .unavailable))
    }

    func confirmFileWrite(_ preview: FileWritePreview) async -> Bool {
        guard let convo = appState?.aiConversation else { return false }
        // 与 confirmCommandExecution 同范式：此方法仅负责 UI 层确认，
        // 「是否跳过确认」由工具层经 isFileWriteAllowedForRun 判断。
        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            convo.pendingWrite = PendingWrite(
                path: preview.path,
                summary: preview.summary,
                diff: preview.diff,
                allowAllForRun: { [weak self] in self?.fileWriteAllowedForRun = true }
            ) { approved in
                convo.pendingWrite = nil
                cont.resume(returning: approved)
            }
        }
    }

    /// Runner 超时/正常结束时拒绝挂起的写入确认（PendingWrite.reject 幂等，
    /// 与 AIConversation.cancelStreaming 的补救路径不冲突）。
    func cancelPendingWriteConfirmation() {
        guard let convo = appState?.aiConversation else { return }
        convo.pendingWrite?.reject()
        convo.pendingWrite = nil
    }
}
