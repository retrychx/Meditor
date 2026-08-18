import Foundation
import Observation

/// 单个文件/目录的 Git 工作区状态（侧边栏标记用）。
enum GitFileStatus: Sendable, Equatable {
    case modified    // M  —— 已跟踪文件有改动（橙色）
    case added       // A  —— 已暂存的新文件（绿色）
    case deleted     // D  —— 已删除（红色）
    case renamed     // R  —— 已重命名（蓝色）
    case untracked   // ?? —— 未跟踪（灰色）
    case conflicted  // U/AA/DD —— 合并冲突（红色）

    /// 行尾单字母标记
    var badge: String {
        switch self {
        case .modified:   return "M"
        case .added:      return "A"
        case .deleted:    return "D"
        case .renamed:    return "R"
        case .untracked:  return "?"
        case .conflicted: return "!"
        }
    }
}

/// 工作区 Git 状态服务：负责检测仓库、执行 `git status --porcelain=v1 -z`、
/// 解析结果并映射回工作区内的文件 URL，供侧边栏文件树显示 M/A/? 等标记。
///
/// 设计要点：
/// - 非 git 工作区完全静默：检测失败即置空状态，不弹错、不打日志噪音；
/// - 工作区可以是仓库的子目录：`rev-parse --show-toplevel` 拿到真正的仓库根，
///   再把仓库相对路径映射回工作区内的绝对 URL，仓库根之外的条目直接丢弃；
/// - 所有 git 调用都在后台线程（Task.detached），主线程只做状态赋值；
/// - 刷新走 300ms 防抖（FSEvents 一次保存可能连发多个事件）。
@MainActor
@Observable
final class GitStatusService {

    // MARK: - State

    /// 工作区内有变更的条目状态（standardizedFileURL → 状态）。
    private(set) var statuses: [URL: GitFileStatus] = [:]
    /// 含有变更后代的目录路径（standardized path），目录行据此显示聚合圆点。
    private(set) var dirtyDirectoryPaths: Set<String> = []
    /// 当前工作区是否为 git 仓库（供 UI 快速短路，非仓库时零开销）。
    private(set) var isGitWorkspace = false

    // MARK: - Private

    /// 已解析的仓库根（相对当前工作区根缓存；nil 表示尚未解析或不是仓库）。
    @ObservationIgnored
    private var repoRoot: URL?
    @ObservationIgnored
    private var workspacePath: String?
    @ObservationIgnored
    private var pendingRefreshWork: DispatchWorkItem?
    /// 防止过期异步结果覆盖新状态（切换工作区时）。
    @ObservationIgnored
    private var generation = 0

    // MARK: - Public API

    /// 防抖刷新（300ms 合并），供 FSEvents 回调等高频触发点使用。
    func scheduleRefresh(rootURL: URL) {
        pendingRefreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.refreshNow(rootURL: rootURL)
        }
        pendingRefreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    /// 立即刷新（打开工作区时调用；git 调用仍在后台执行）。
    func refreshNow(rootURL: URL) {
        generation &+= 1
        let gen = generation

        // 工作区切换：重置缓存，重新探测仓库根
        let wsPath = rootURL.standardizedFileURL.path
        if wsPath != workspacePath {
            workspacePath = wsPath
            repoRoot = nil
            statuses = [:]
            dirtyDirectoryPaths = []
            isGitWorkspace = false
        }

        let cachedRepoRoot = repoRoot
        Task.detached(priority: .utility) { [weak self] in
            // 1. 解析仓库根（首次或工作区变化后）
            let root: URL?
            if let cachedRepoRoot {
                root = cachedRepoRoot
            } else {
                root = Self.findRepoRoot(of: rootURL)
            }
            guard let root else {
                // 非 git 工作区：静默清空
                await self?.apply(statuses: [:], dirtyDirs: [], repoRoot: nil, generation: gen)
                return
            }

            // 2. 获取 porcelain 状态
            guard let data = Self.runGit(["status", "--porcelain=v1", "-z"], in: root) else {
                await self?.apply(statuses: [:], dirtyDirs: [], repoRoot: root, generation: gen)
                return
            }

            // 3. 解析 + 映射回工作区
            let entries = Self.parsePorcelain(data)
            let mapped = Self.mapToWorkspace(entries, repoRoot: root, workspaceRoot: rootURL)
            await self?.apply(statuses: mapped.statuses, dirtyDirs: mapped.dirtyDirs,
                              repoRoot: root, generation: gen)
        }
    }

    /// 清空全部状态（关闭工作区时）。
    func clear() {
        pendingRefreshWork?.cancel()
        generation &+= 1
        statuses = [:]
        dirtyDirectoryPaths = []
        isGitWorkspace = false
        repoRoot = nil
        workspacePath = nil
    }

    func status(for url: URL) -> GitFileStatus? {
        statuses[url.standardizedFileURL]
    }

    func directoryContainsChanges(_ url: URL) -> Bool {
        dirtyDirectoryPaths.contains(url.standardizedFileURL.path)
    }

    // MARK: - Apply (MainActor)

    private func apply(statuses: [URL: GitFileStatus], dirtyDirs: Set<String>,
                       repoRoot: URL?, generation gen: Int) {
        guard gen == generation else { return }   // 过期结果直接丢弃
        self.repoRoot = repoRoot
        self.statuses = statuses
        self.dirtyDirectoryPaths = dirtyDirs
        self.isGitWorkspace = repoRoot != nil
    }

    // MARK: - Git 调用（后台线程）

    /// 向上查找工作区所在仓库的根目录；不是仓库时返回 nil。
    nonisolated static func findRepoRoot(of workspace: URL) -> URL? {
        // 未装 Xcode 命令行工具的机器上 /usr/bin/git 是 stub，执行它会弹
        // 「安装命令行开发者工具」系统框——先用 xcode-select -p 探测，不可用就静默跳过
        guard runProcess(executable: "/usr/bin/xcode-select", arguments: ["-p"], in: workspace) != nil,
              let data = runGit(["rev-parse", "--show-toplevel"], in: workspace),
              let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        return URL(fileURLWithPath: text).standardizedFileURL
    }

    /// 同步执行 git 命令并返回 stdout（调用方负责切到后台线程）。
    /// 任何失败（找不到 git、非零退出码）都返回 nil —— 静默降级。
    nonisolated static func runGit(_ arguments: [String], in directory: URL) -> Data? {
        runProcess(executable: "/usr/bin/git", arguments: arguments, in: directory)
    }

    /// 同步执行指定可执行文件并返回 stdout；找不到/启动失败/非零退出码都返回 nil。
    nonisolated static func runProcess(executable: String, arguments: [String], in directory: URL) -> Data? {
        guard FileManager.default.fileExists(atPath: executable) else { return nil }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = arguments
        proc.currentDirectoryURL = directory

        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = FileHandle.nullDevice

        do { try proc.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return nil }
        return data
    }

    // MARK: - porcelain 解析（纯函数，便于测试）

    /// 解析 `git status --porcelain=v1 -z` 的输出。
    ///
    /// -z 格式：每条记录为 `XY <path>\0`，路径不做 C 风格引号转义，
    /// 空格/中文/换行均可原样出现；重命名/复制条目紧跟一条源路径记录：
    /// `XY 新路径\0旧路径\0`。
    /// 忽略 `!!`（被 ignore 的文件）——侧边栏不显示。
    nonisolated static func parsePorcelain(_ data: Data) -> [(path: String, status: GitFileStatus)] {
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { return [] }
        // -z 以 NUL 分隔，末尾可能有空段，split(omittingEmptySubsequences) 一并处理
        let records = text.split(separator: "\0", omittingEmptySubsequences: true)
        var result: [(path: String, status: GitFileStatus)] = []
        var i = 0
        while i < records.count {
            let record = records[i]
            guard record.count >= 4 else { i += 1; continue }   // 至少 "XY p"
            let x = record[record.startIndex]
            let y = record[record.index(after: record.startIndex)]
            // 第 3 个字符是空格，路径从第 4 个字符开始
            let path = String(record.dropFirst(3))

            // 重命名/复制：-z 下源路径是紧随其后的独立记录
            let isRename = x == "R" || y == "R" || x == "C" || y == "C"
            if isRename { i += 1 }   // 跳过旧路径记录

            if let status = statusFromCode(x: x, y: y) {
                result.append((path: path, status: status))
            }
            i += 1
        }
        return result
    }

    /// 由 XY 双字符状态码推导单一标记状态。
    /// 优先级：冲突 > 未跟踪 > 重命名 > 新增 > 删除 > 修改。
    /// `!!`（ignored）返回 nil，表示不显示。
    nonisolated static func statusFromCode(x: Character, y: Character) -> GitFileStatus? {
        if x == "!" { return nil }                       // !! ignored
        if x == "?" { return .untracked }                // ?? untracked
        if x == "U" || y == "U"
            || (x == "A" && y == "A") || (x == "D" && y == "D") {
            return .conflicted
        }
        if x == "R" || y == "R" { return .renamed }
        if x == "A" { return .added }                    // 含 AM：新文件+追加改动，仍按新增显示
        if x == "D" || y == "D" { return .deleted }
        if x == "M" || y == "M" { return .modified }
        if x == "C" || y == "C" { return .added }        // 复制按新增对待
        return .modified                                  // 兜底
    }

    /// 把仓库相对路径条目映射为工作区内的绝对 URL，并计算脏目录集合。
    ///
    /// - 仓库根之外的条目（工作区是仓库子目录时，仓库里其他目录的变更）直接丢弃；
    /// - 脏目录 = 每个变更文件在工作区内的所有祖先目录（不含工作区根本身，
    ///   根目录不在文件树里显示）；
    /// - 未跟踪目录条目（路径以 `/` 结尾）去掉尾斜杠后按目录自身状态显示。
    nonisolated static func mapToWorkspace(
        _ entries: [(path: String, status: GitFileStatus)],
        repoRoot: URL,
        workspaceRoot: URL
    ) -> (statuses: [URL: GitFileStatus], dirtyDirs: Set<String>) {
        let ws = workspaceRoot.standardizedFileURL
        let wsPath = ws.path
        var statuses: [URL: GitFileStatus] = [:]
        var dirtyDirs: Set<String> = []

        for entry in entries {
            // 未跟踪目录的尾斜杠只影响路径拼接，统一去掉
            let rel = entry.path.hasSuffix("/") ? String(entry.path.dropLast()) : entry.path
            guard !rel.isEmpty else { continue }
            let fileURL = repoRoot.appendingPathComponent(rel).standardizedFileURL
            let filePath = fileURL.path

            // 只保留工作区子树内的条目
            guard filePath == wsPath || filePath.hasPrefix(wsPath + "/") else { continue }
            statuses[fileURL] = entry.status

            // 聚合：标记所有祖先目录（工作区根除外）
            var dir = fileURL.deletingLastPathComponent()
            while dir.path.hasPrefix(wsPath + "/") {
                if !dirtyDirs.insert(dir.path).inserted { break }   // 已收录则上层也已收录
                dir = dir.deletingLastPathComponent()
            }
        }
        return (statuses, dirtyDirs)
    }
}
