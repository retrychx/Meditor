import Foundation
import Observation

/// 当前打开文档的状态，以及"用其他应用打开"传入文件的处理。
///
/// 外部传入的是 security-scoped URL（只在回调期间可读），因此打开时立即
/// 读取内容并拷贝一份到 App 沙盒 Documents/Inbox/ 下，让 Agent 的工作区
/// 工具（限定在 Documents 目录）也能看到该文件。
@MainActor
@Observable
final class DocumentStore {

    enum ContentKind: String {
        case markdown
        case html
        case other
    }

    /// 文档纯文本内容（编辑即改这里）。
    var text: String = ""
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

    init() {
        if let rel = UserDefaults.standard.string(forKey: Self.lastDocKey) {
            let url = Self.workspaceURL.appendingPathComponent(rel)
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

    static var workspaceURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private static var inboxURL: URL {
        workspaceURL.appendingPathComponent("Inbox", isDirectory: true)
    }

    // MARK: - Open incoming file

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
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        }
        do {
            let data = try Data(contentsOf: url)
            guard let content = String(data: data, encoding: .utf8)
                             ?? String(data: data, encoding: .isoLatin1) else {
                lastError = "无法解码文件：\(url.lastPathComponent)"
                return
            }
            try FileManager.default.createDirectory(at: Self.inboxURL, withIntermediateDirectories: true)
            let dest = Self.inboxURL.appendingPathComponent(url.lastPathComponent)
            try content.write(to: dest, atomically: true, encoding: .utf8)
            sandboxURL = dest
            fileName = url.lastPathComponent
            text     = content
            lastError = nil
            remember(dest)
        } catch {
            lastError = "打开失败：\(error.localizedDescription)"
        }
    }

    /// 打开沙盒工作区内的文件（Agent open_file 工具用）。
    func loadFromSandbox(_ url: URL) -> Bool {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return false }
        sandboxURL = url
        fileName   = url.lastPathComponent
        text       = content
        lastError  = nil
        remember(url)
        return true
    }

    /// 记录相对路径，供下次启动恢复。
    private func remember(_ url: URL) {
        let base = Self.workspaceURL.standardizedFileURL.path
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

    /// 撤销本轮 AI 改动，恢复到 run 前内容。
    func undoAIChanges() {
        guard let snapshot = aiSnapshot else { return }
        try? replaceContent(snapshot)
        aiSnapshot = nil
        aiFinalText = nil
    }

    /// 全量替换内容并写回沙盒副本。
    func replaceContent(_ newContent: String) throws {
        guard let url = sandboxURL else { throw AgentContextError.noActiveDocument }
        try newContent.write(to: url, atomically: true, encoding: .utf8)
        text = newContent
    }

    /// 沙盒副本内容变更后同步内存（patchFile 等直接写盘的路径用）。
    func reloadIfCurrent(_ url: URL) {
        guard url.standardizedFileURL == sandboxURL?.standardizedFileURL,
              let content = try? String(contentsOf: url, encoding: .utf8) else { return }
        text = content
    }
}
