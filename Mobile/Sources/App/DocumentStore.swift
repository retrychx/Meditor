import Foundation
import Observation

/// 当前打开文档的状态，以及"用其他应用打开"传入文件的处理。
///
/// 外部传入的是 security-scoped URL（只在回调期间可读），因此打开时立即
/// 读取内容并拷贝一份到 App 沙盒 Documents/Opened/ 下（系统投递用的
/// Documents/Inbox/ 可能被系统清理，Opened/ 才是持久副本层），让 Agent 的
/// 工作区工具（限定在 Documents 目录）也能看到该文件。
@MainActor
@Observable
final class DocumentStore {

    enum ContentKind: String {
        case markdown
        case html
        case other
    }

    /// 文档纯文本内容（编辑经 applyManualEdit 改这里，以便触发自动保存）。
    private(set) var text: String = ""
    /// 展示用文件名。
    var fileName: String = ""
    /// 沙盒内的持久化副本（nil = 尚无打开文档）。
    private(set) var sandboxURL: URL? = nil
    /// 最近一次打开失败的错误信息（UI 简单展示）。
    var lastError: String? = nil
    /// 预览 / 编辑切换（true = 预览）。
    var showPreview: Bool = true

    var hasDocument: Bool { sandboxURL != nil }

    /// 上次打开文档在沙盒 Documents 下的相对路径（重启后恢复）。
    private static let lastDocKey = "lastDocumentRelativePath"

    /// 工作区目录提供者：默认返回沙盒 Documents，测试可注入临时目录。
    private let workspaceProvider: () -> URL

    /// 当前工作区目录。
    var workspace: URL { workspaceProvider() }

    init(workspaceProvider: @escaping () -> URL = { DocumentStore.workspaceURL }) {
        self.workspaceProvider = workspaceProvider
        if let rel = UserDefaults.standard.string(forKey: Self.lastDocKey) {
            let url = workspaceProvider().appendingPathComponent(rel)
            if let content = try? String(contentsOf: url, encoding: .utf8) {
                sandboxURL = url
                fileName   = url.lastPathComponent
                text       = content
            }
        }
    }

    var kind: ContentKind {
        switch (sandboxURL?.pathExtension ?? fileName.split(separator: ".").last.map(String.init) ?? "").lowercased() {
        case "md", "markdown": return .markdown
        case "html", "htm":    return .html
        default:               return .other
        }
    }

    // MARK: - Workspace（Agent 工作区 = 沙盒 Documents 目录）

    /// 默认工作区：沙盒 Documents 目录（init 的 workspaceProvider 默认值来源）。
    /// nonisolated：默认值表达式在非隔离上下文中求值；FileManager 调用本身线程安全。
    nonisolated static var workspaceURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// 持久副本目录：Documents/Opened/。系统"用其他应用打开"投递到 Inbox/，
    /// 但 Inbox 随时可能被系统清理，因此打开时立即转存到这里。
    private var openedURL: URL {
        workspace.appendingPathComponent("Opened", isDirectory: true)
    }

    // MARK: - Open incoming file

    /// 打开文件大小上限：10 MB。
    private static let maxFileBytes = 10 * 1024 * 1024

    /// 处理 .onOpenURL 传入的文件（微信等 App "用其他应用打开"）。
    /// 注：Info.plist 已关闭 in-place 打开，系统会先把文件拷进沙盒 Documents/Inbox，
    /// 从源头规避微信/iCloud 原址读取的权限问题；文件选择器来的 URL 仍是
    /// security-scoped，下面的 scope 访问必须保留。
    func openIncoming(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        // iCloud 占位文件（真机未下载时读取会报"无权限/不存在"）：先触发下载
        if let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey]),
           values.isUbiquitousItem == true {
            do {
                try FileManager.default.startDownloadingUbiquitousItem(at: url)
            } catch {
                print("[DocumentStore] 触发 iCloud 下载失败：\(error.localizedDescription)")
            }
        }
        do {
            let data = try Data(contentsOf: url)
            guard data.count <= Self.maxFileBytes else {
                lastError = "文件过大（超过 10 MB），暂不支持打开：\(url.lastPathComponent)"
                return
            }
            let content: String
            if let utf8 = String(data: data, encoding: .utf8) {
                content = utf8
            } else {
                // 二进制嗅探：UTF-8 解码失败且前 8KB 含 NUL 字节 → 不是文本，拒绝打开。
                // isoLatin1 兜底仅用于无 NUL 的旧编码文本（否则它必然成功，把二进制显示成乱码）。
                if data.prefix(8 * 1024).contains(0) {
                    lastError = "不支持二进制文件：\(url.lastPathComponent)"
                    return
                }
                guard let legacy = String(data: data, encoding: .isoLatin1) else {
                    lastError = "无法解码文件：\(url.lastPathComponent)"
                    return
                }
                content = legacy
            }
            try FileManager.default.createDirectory(at: openedURL, withIntermediateDirectories: true)
            let dest = uniqueDestination(for: url.lastPathComponent)
            try content.write(to: dest, atomically: true, encoding: .utf8)
            autosaveTask?.cancel()
            sandboxURL = dest
            fileName = dest.lastPathComponent
            text     = content
            lastError = nil
            remember(dest)
        } catch {
            lastError = "打开失败：\(error.localizedDescription)"
        }
    }

    /// 在 Opened/ 下为传入文件名生成不冲突的目标 URL：同名已存在则追加
    /// "-2"、"-3"……递增后缀（如 "name-2.md"），避免互覆。
    private func uniqueDestination(for fileName: String) -> URL {
        let ext  = (fileName as NSString).pathExtension
        let base = (fileName as NSString).deletingPathExtension
        var candidate = openedURL.appendingPathComponent(fileName)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let name = ext.isEmpty ? "\(base)-\(n)" : "\(base)-\(n).\(ext)"
            candidate = openedURL.appendingPathComponent(name)
            n += 1
        }
        return candidate
    }

    /// 打开沙盒工作区内的文件（Agent open_file 工具用）。
    func loadFromSandbox(_ url: URL) -> Bool {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return false }
        autosaveTask?.cancel()
        sandboxURL = url
        fileName   = url.lastPathComponent
        text       = content
        lastError  = nil
        remember(url)
        return true
    }

    /// 记录相对路径，供下次启动恢复。
    private func remember(_ url: URL) {
        let base = workspace.standardizedFileURL.path
        let full = url.standardizedFileURL.path
        let rel = full.hasPrefix(base + "/") ? String(full.dropFirst(base.count + 1)) : url.lastPathComponent
        UserDefaults.standard.set(rel, forKey: Self.lastDocKey)
    }

    // MARK: - Mutations（Agent 文档写工具用）

    /// AI 改动快照：一次 run 前的文档内容（每次 run 只留第一份）。
    private(set) var aiSnapshot: String? = nil
    /// AI 最后一次写入后的内容；用户之后再手动编辑，撤销入口自动隐藏（避免覆盖用户输入）。
    private(set) var aiFinalText: String? = nil
    /// 当前是否可以撤销 AI 改动。
    var canUndoAI: Bool { aiSnapshot != nil && aiFinalText == text }

    /// 一次 AI run 开始：清空上一轮快照。
    func beginAIRun() {
        aiSnapshot = nil
        aiFinalText = nil
    }

    /// Agent 写工具的入口（write_document / patch_document / insert_at_cursor）：
    /// 首次写入前留快照，写后记录最终态。
    func noteAIReplace(_ newContent: String) throws {
        if aiSnapshot == nil { aiSnapshot = text }
        try replaceContent(newContent)
        aiFinalText = text
    }

    /// 撤销本轮 AI 改动，恢复到 run 前内容（经 replaceContent 立即写盘）。
    /// 写盘失败必须让用户知道：设置 lastError（UI 已有展示），并保留快照以便重试。
    func undoAIChanges() {
        guard let snapshot = aiSnapshot else { return }
        do {
            try replaceContent(snapshot)
            aiSnapshot = nil
            aiFinalText = nil
        } catch {
            print("[DocumentStore] 撤销 AI 改动写盘失败：\(error.localizedDescription)")
            lastError = "撤销失败：\(error.localizedDescription)"
        }
    }

    /// 全量替换内容并写回沙盒副本（AI 写工具走这里，立即落盘）。
    func replaceContent(_ newContent: String) throws {
        guard let url = sandboxURL else { throw AgentContextError.noActiveDocument }
        try newContent.write(to: url, atomically: true, encoding: .utf8)
        // 已立即写盘，取消挂起的防抖自动保存，避免与 AI 写冲突 / 重复写。
        autosaveTask?.cancel()
        text = newContent
    }

    /// 沙盒副本内容变更后同步内存（patchFile 等直接写盘的路径用）。
    func reloadIfCurrent(_ url: URL) {
        guard url.standardizedFileURL == sandboxURL?.standardizedFileURL,
              let content = try? String(contentsOf: url, encoding: .utf8) else { return }
        text = content
    }

    // MARK: - Autosave（手动编辑防抖写盘）

    /// 防抖延迟：停止输入 ~0.8s 后写回沙盒副本。
    private static let autosaveDelayNanos: UInt64 = 800_000_000

    /// 挂起的自动保存任务（新任务取消旧任务实现防抖）。
    private var autosaveTask: Task<Void, Never>?

    /// 手动编辑入口（TextEditor 绑定用）：更新内容并调度防抖自动保存。
    /// 程序化变更（AI 写工具 / 打开文件 / 撤销）不走这里——它们已立即写盘。
    func applyManualEdit(_ newText: String) {
        text = newText
        scheduleAutosave()
    }

    /// 防抖自动保存：~0.8s 无新编辑后把当前 text 写回沙盒副本。
    private func scheduleAutosave() {
        guard let url = sandboxURL else { return }
        autosaveTask?.cancel()
        autosaveTask = Task {
            try? await Task.sleep(nanoseconds: Self.autosaveDelayNanos)
            guard !Task.isCancelled else { return }
            do {
                try self.text.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                print("[DocumentStore] 自动保存失败：\(error.localizedDescription)")
                self.lastError = "自动保存失败：\(error.localizedDescription)"
            }
        }
    }
}
