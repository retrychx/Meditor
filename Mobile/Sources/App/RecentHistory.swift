import Foundation
import Observation

/// 最近文档记录的管理：工作区扫描、snippet 缓存、排序/裁剪/持久化。
/// 与 DocumentStore 分离，聚焦文件列表的扫描与历史维护。
/// 视图仅需读取列表时可单独观察此类，不影响 DocumentStore 的文档内容。
@MainActor
@Observable
final class RecentHistory {

    // MARK: - Types

    /// 最近文档记录：相对路径（稳定标识）+ 展示名 + 最后打开时间 + 置顶标志 + 首行摘要。
    /// 沙盒外文档（iCloud Drive 等原地打开）：relativePath 存打开时的完整路径，
    /// bookmarkData 存 security-scoped bookmark，跨启动用它恢复访问权。
    struct RecentDocument: Codable, Equatable {
        var relativePath: String
        var fileName: String
        var lastOpened: Date
        var pinned: Bool
        var snippet: String = ""
        /// 沙盒外文档的 security-scoped bookmark；nil 表示工作区内文档。
        var bookmarkData: Data? = nil
        /// 不带扩展名的文件名。
        var baseName: String {
            (fileName as NSString).deletingPathExtension
        }
        /// 是否沙盒外原地打开的文档（iCloud Drive / 其他文件 Provider）。
        var isExternal: Bool { bookmarkData != nil }
    }

    // MARK: - State

    /// 最近文档列表（已排序：置顶在前，其余按最后打开时间倒序）。
    private(set) var documents: [RecentDocument] = []

    private static let recentsKey = "recentDocuments"
    private static let maxRecents = 50
    static let documentExtensions: Set<String> = ["md", "markdown", "html", "htm"]

    /// 防抖持久化任务。
    private var persistTask: Task<Void, Never>?
    /// 上次扫描时间戳：2s 内避免重复扫描（onAppear 只触发一次已有 tab 优化，此防抖作为兜底）。
    private var lastScanned: Date = .distantPast

    // MARK: - Workspace

    private let workspaceProvider: () -> URL
    private var _workspace: URL? = nil

    var workspace: URL {
        if let cached = _workspace { return cached }
        let w = workspaceProvider()
        _workspace = w
        return w
    }

    /// 持久副本目录：Documents/Opened/。
    private var openedURL: URL {
        workspace.appendingPathComponent("Opened", isDirectory: true)
    }

    /// 默认工作区。
    nonisolated static var workspaceURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    // MARK: - Init

    init(workspaceProvider: @escaping () -> URL = { RecentHistory.workspaceURL }) {
        self.workspaceProvider = workspaceProvider
        if let data = UserDefaults.standard.data(forKey: Self.recentsKey),
           let decoded = try? JSONDecoder().decode([RecentDocument].self, from: data) {
            documents = decoded
        }
    }

    // MARK: - API

    /// 扫描工作区并入最近列表，已不存在的清掉。2s 内防抖。
    func refreshWorkspaceDocuments() {
        let now = Date()
        guard now.timeIntervalSince(lastScanned) > 2 else { return }
        lastScanned = now
        var scanned: [String: (name: String, date: Date, url: URL)] = [:]
        for dir in [workspace, openedURL] {
            guard let urls = try? FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]) else { continue }
            for url in urls {
                guard Self.documentExtensions.contains(url.pathExtension.lowercased()),
                      let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
                      values.isRegularFile == true else { continue }
                scanned[relativePath(for: url)] = (url.lastPathComponent, values.contentModificationDate ?? .distantPast, url)
            }
        }
        let before = documents.count
        documents.removeAll { rec in
            let dir = (rec.relativePath as NSString).deletingLastPathComponent
            let inScannedScope = dir.isEmpty || dir == "." || dir == "Opened"
            return inScannedScope && scanned[rec.relativePath] == nil
        }
        var changed = documents.count != before
        for (rel, info) in scanned {
            if let idx = documents.firstIndex(where: { $0.relativePath == rel }) {
                if documents[idx].fileName != info.name {
                    documents[idx].fileName = info.name
                    changed = true
                }
            } else {
                documents.append(RecentDocument(
                    relativePath: rel, fileName: info.name, lastOpened: info.date, pinned: false))
                changed = true
            }
        }
        if changed {
            sortRecents()
            trimRecents()
            persistRecents()
        }
        Task { await refreshSnippets(for: scanned) }
    }

    /// 新增/更新一条最近记录。沙盒外文档传 bookmark，以其完整路径作为 relativePath 标识。
    func touchRecent(_ url: URL, date: Date = Date(), bookmark: Data? = nil) {
        let rel = bookmark != nil ? url.standardizedFileURL.path : relativePath(for: url)
        if let idx = documents.firstIndex(where: { $0.relativePath == rel }) {
            documents[idx].fileName = url.lastPathComponent
            documents[idx].lastOpened = date
            documents[idx].bookmarkData = bookmark
        } else {
            documents.append(RecentDocument(
                relativePath: rel, fileName: url.lastPathComponent, lastOpened: date,
                pinned: false, bookmarkData: bookmark))
        }
        sortRecents()
        trimRecents()
        persistRecents()
    }

    /// bookmark 解析后文件位置已变化（stale）：更新记录的标识与书签。
    func updateExternalEntry(oldRel: String, url: URL, bookmark: Data) {
        guard let idx = documents.firstIndex(where: { $0.relativePath == oldRel }) else { return }
        documents[idx].relativePath = url.standardizedFileURL.path
        documents[idx].fileName = url.lastPathComponent
        documents[idx].bookmarkData = bookmark
        persistRecents()
    }

    /// 置顶 / 取消置顶。
    func togglePin(_ rel: String) {
        guard let idx = documents.firstIndex(where: { $0.relativePath == rel }) else { return }
        documents[idx].pinned.toggle()
        sortRecents()
        persistRecents()
    }

    /// 更新某条记录的相对路径（重命名后用）。
    func updatePath(old: String, new: String, newName: String) {
        guard let idx = documents.firstIndex(where: { $0.relativePath == old }) else { return }
        documents[idx].relativePath = new
        documents[idx].fileName = newName
        persistRecents()
    }

    /// 移除一条记录（删除文件后用）。
    func remove(_ rel: String) {
        documents.removeAll { $0.relativePath == rel }
        persistRecents()
    }

    // MARK: - Internal

    private func relativePath(for url: URL) -> String {
        let base = workspace.standardizedFileURL.path
        let full = url.standardizedFileURL.path
        return full.hasPrefix(base + "/") ? String(full.dropFirst(base.count + 1)) : url.lastPathComponent
    }

    private func refreshSnippets(for scanned: [String: (name: String, date: Date, url: URL)]) async {
        for (rel, info) in scanned {
            guard let idx = documents.firstIndex(where: { $0.relativePath == rel }),
                  documents[idx].snippet.isEmpty else { continue }
            let snippet = await Task.detached { Self.readSnippet(from: info.url) }.value
            documents[idx].snippet = snippet
        }
    }

    nonisolated private static func readSnippet(from url: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 4096), !data.isEmpty else { return "" }
        let raw = String(decoding: data, as: UTF8.self)
        let lines = raw.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .prefix(3)
            .map { $0.replacingOccurrences(of: "^[#>\\-*+\\s]+", with: "", options: .regularExpression) }
        return lines.joined(separator: "  ")
    }

    private func sortRecents() {
        documents.sort { a, b in
            if a.pinned != b.pinned { return a.pinned }
            return a.lastOpened > b.lastOpened
        }
    }

    private func trimRecents() {
        while documents.count > Self.maxRecents,
              let idx = documents.lastIndex(where: { !$0.pinned }) {
            documents.remove(at: idx)
        }
    }

    private func persistRecents() {
        persistTask?.cancel()
        persistTask = Task {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            UserDefaults.standard.set(try? JSONEncoder().encode(documents), forKey: Self.recentsKey)
        }
    }
}
