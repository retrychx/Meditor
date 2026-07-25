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

    /// 最近文档记录：相对路径（稳定标识）+ 展示名 + 最后打开时间 + 置顶标志。
    struct RecentDocument: Codable, Equatable {
        var relativePath: String
        var fileName: String
        var lastOpened: Date
        var pinned: Bool
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

    /// 最近文档列表（已排序：置顶在前，其余按最后打开时间倒序）。
    private(set) var recentDocuments: [RecentDocument] = []
    /// 最近文档持久化 key / 条数上限 / 纳入列表的扩展名。
    private static let recentsKey = "recentDocuments"
    private static let maxRecents = 50
    private static let documentExtensions: Set<String> = ["md", "markdown", "html", "htm"]

    /// 工作区目录提供者：默认返回沙盒 Documents，测试可注入临时目录。
    private let workspaceProvider: () -> URL

    /// 当前工作区目录。
    var workspace: URL { workspaceProvider() }

    init(workspaceProvider: @escaping () -> URL = { DocumentStore.workspaceURL }) {
        self.workspaceProvider = workspaceProvider
        if let data = UserDefaults.standard.data(forKey: Self.recentsKey),
           let decoded = try? JSONDecoder().decode([RecentDocument].self, from: data) {
            recentDocuments = decoded
        }
        if let rel = UserDefaults.standard.string(forKey: Self.lastDocKey) {
            let url = workspaceProvider().appendingPathComponent(rel)
            if let content = try? String(contentsOf: url, encoding: .utf8) {
                sandboxURL = url
                fileName   = url.lastPathComponent
                text       = content
                touchRecent(url)
            }
        }
        // 把工作区里现存的文档（含微信转存进来的）补入最近列表。
        refreshWorkspaceDocuments()
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
            // 去重：Opened/ 已有同名且内容一致的文件 → 直接打开现有副本，
            // 否则才写新副本（同名不同内容才加 -2/-3 后缀），不再开一次多一份。
            var dest = openedURL.appendingPathComponent(url.lastPathComponent)
            if let existing = try? String(contentsOf: dest, encoding: .utf8), existing == content {
                // 内容一致，复用现有副本（mtime 不刷新，避免误当新文件）。
            } else {
                dest = uniqueDestination(for: url.lastPathComponent)
                try content.write(to: dest, atomically: true, encoding: .utf8)
            }
            // 系统投递到 Inbox 的原件：转存/复用成功后清理，杜绝一份文件变两份。
            let inboxDir = workspace.appendingPathComponent("Inbox", isDirectory: true).standardizedFileURL
            if url.standardizedFileURL.path.hasPrefix(inboxDir.path + "/") {
                try? FileManager.default.removeItem(at: url)
            }
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

    /// 记录相对路径，供下次启动恢复；同时更新最近文档记录。
    private func remember(_ url: URL) {
        UserDefaults.standard.set(relativePath(for: url), forKey: Self.lastDocKey)
        touchRecent(url)
    }

    /// 沙盒 Documents 下的相对路径（不在工作区内则退化为文件名）。
    private func relativePath(for url: URL) -> String {
        let base = workspace.standardizedFileURL.path
        let full = url.standardizedFileURL.path
        return full.hasPrefix(base + "/") ? String(full.dropFirst(base.count + 1)) : url.lastPathComponent
    }

    // MARK: - 最近文档

    /// 新增/更新一条最近记录（已有路径保留置顶标志），重排、裁剪并持久化。
    private func touchRecent(_ url: URL, date: Date = Date()) {
        let rel = relativePath(for: url)
        if let idx = recentDocuments.firstIndex(where: { $0.relativePath == rel }) {
            recentDocuments[idx].fileName = url.lastPathComponent
            recentDocuments[idx].lastOpened = date
        } else {
            recentDocuments.append(RecentDocument(
                relativePath: rel, fileName: url.lastPathComponent, lastOpened: date, pinned: false))
        }
        sortRecents()
        trimRecents()
        persistRecents()
    }

    /// 扫描工作区（Documents 根 + Opened/）现存的文档文件并入最近列表：
    /// 未记录的文件以修改时间作为最后打开时间补入（微信等渠道转存进来的也能被看到）；
    /// 记录里文件已不存在的（仅限这两个扫描范围内）顺手清掉，不留僵尸条目。
    func refreshWorkspaceDocuments() {
        var scanned: [String: (name: String, date: Date)] = [:]
        for dir in [workspace, openedURL] {
            guard let urls = try? FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]) else { continue }
            for url in urls {
                guard Self.documentExtensions.contains(url.pathExtension.lowercased()),
                      let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
                      values.isRegularFile == true else { continue }
                scanned[relativePath(for: url)] = (url.lastPathComponent, values.contentModificationDate ?? .distantPast)
            }
        }
        var changed = false
        let before = recentDocuments.count
        recentDocuments.removeAll { rec in
            let dir = (rec.relativePath as NSString).deletingLastPathComponent
            let inScannedScope = dir.isEmpty || dir == "." || dir == "Opened"
            return inScannedScope && scanned[rec.relativePath] == nil
        }
        changed = recentDocuments.count != before
        for (rel, info) in scanned {
            if let idx = recentDocuments.firstIndex(where: { $0.relativePath == rel }) {
                if recentDocuments[idx].fileName != info.name {
                    recentDocuments[idx].fileName = info.name
                    changed = true
                }
            } else {
                recentDocuments.append(RecentDocument(
                    relativePath: rel, fileName: info.name, lastOpened: info.date, pinned: false))
                changed = true
            }
        }
        if changed {
            sortRecents()
            trimRecents()
            persistRecents()
        }
    }

    /// 置顶 / 取消置顶。
    func togglePin(_ rel: String) {
        guard let idx = recentDocuments.firstIndex(where: { $0.relativePath == rel }) else { return }
        recentDocuments[idx].pinned.toggle()
        sortRecents()
        persistRecents()
    }

    /// 重命名沙盒内文件（只改文件名，保留扩展名）：目标名冲突时自动追加 "-2" 递增后缀。
    /// 同步更新最近记录；若改的是当前打开文档，先落盘 pending 编辑，再同步当前状态与恢复路径。
    /// 返回实际采用的新文件名，失败返回 nil。
    @discardableResult
    func renameDocument(at rel: String, to newBaseName: String) -> String? {
        let trimmed = newBaseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let oldURL = workspace.appendingPathComponent(rel)
        guard FileManager.default.fileExists(atPath: oldURL.path) else { return nil }

        let ext = (rel as NSString).pathExtension
        let dir = (rel as NSString).deletingLastPathComponent
        let dirURL = dir.isEmpty || dir == "." ? workspace : workspace.appendingPathComponent(dir, isDirectory: true)
        // 原名未变：直接成功返回，不做无意义的移动。
        let desired = ext.isEmpty ? trimmed : "\(trimmed).\(ext)"
        if desired == oldURL.lastPathComponent { return desired }
        var candidate = desired
        var n = 2
        while FileManager.default.fileExists(atPath: dirURL.appendingPathComponent(candidate).path) {
            candidate = ext.isEmpty ? "\(trimmed)-\(n)" : "\(trimmed)-\(n).\(ext)"
            n += 1
        }
        let newURL = dirURL.appendingPathComponent(candidate)
        let isCurrent = sandboxURL?.standardizedFileURL == oldURL.standardizedFileURL
        if isCurrent {
            // 挂起的防抖保存捕获的是旧 URL，移动前先落盘并取消，避免旧文件被重建。
            autosaveTask?.cancel()
            try? text.write(to: oldURL, atomically: true, encoding: .utf8)
        }
        guard (try? FileManager.default.moveItem(at: oldURL, to: newURL)) != nil else { return nil }

        let newRel = relativePath(for: newURL)
        if let idx = recentDocuments.firstIndex(where: { $0.relativePath == rel }) {
            recentDocuments[idx].relativePath = newRel
            recentDocuments[idx].fileName = candidate
            persistRecents()
        }
        if isCurrent {
            sandboxURL = newURL
            fileName   = candidate
            UserDefaults.standard.set(newRel, forKey: Self.lastDocKey)
        }
        return candidate
    }

    /// 删除沙盒文件 + 最近记录；若删的是当前打开文档，回到无文档空态。
    func deleteDocument(at rel: String) {
        let url = workspace.appendingPathComponent(rel)
        let wasCurrent = sandboxURL?.standardizedFileURL == url.standardizedFileURL
        try? FileManager.default.removeItem(at: url)
        recentDocuments.removeAll { $0.relativePath == rel }
        persistRecents()
        if wasCurrent {
            autosaveTask?.cancel()
            sandboxURL = nil
            fileName   = ""
            text       = ""
            aiSnapshot = nil
            aiFinalText = nil
            UserDefaults.standard.removeObject(forKey: Self.lastDocKey)
        }
    }

    /// 排序：置顶在前，其余按最后打开时间倒序。
    private func sortRecents() {
        recentDocuments.sort { a, b in
            if a.pinned != b.pinned { return a.pinned }
            return a.lastOpened > b.lastOpened
        }
    }

    /// 裁剪到上限：优先淘汰最旧的非置顶记录。
    private func trimRecents() {
        while recentDocuments.count > Self.maxRecents,
              let idx = recentDocuments.lastIndex(where: { !$0.pinned }) {
            recentDocuments.remove(at: idx)
        }
    }

    private func persistRecents() {
        UserDefaults.standard.set(try? JSONEncoder().encode(recentDocuments), forKey: Self.recentsKey)
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
