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
    func openIncoming(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
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
        return true
    }

    // MARK: - Mutations（Agent 文档写工具用）

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
