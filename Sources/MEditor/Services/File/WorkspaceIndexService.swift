import Foundation

// MARK: - Search Match

/// 单条工作区搜索结果：相对路径 + 1-based 行号 + 行原文。
/// lineNumber == 0 表示「文件名匹配」（无行内容，仅供 UI 全局搜索展示文件行）。
struct WorkspaceSearchMatch: Sendable, Equatable {
    let relativePath: String
    let lineNumber: Int
    let line: String
}

// MARK: - WorkspaceIndexService

/// 工作区全文内容索引（macOS / iOS 共享层，纯 Foundation，无外部依赖）。
///
/// 生命周期：打开工作区时 `buildIndex` 全量建立 → 文件变化（FSEvents / 保存）
/// 走 `scheduleRefresh` / `updateFile` 增量更新 → 关闭工作区 `clear` 释放。
/// 消费方：全局搜索 UI（⌘⇧F）与 Agent 的 search_workspace 工具共用同一实例。
///
/// 数据结构取舍：不建倒排索引，而是把每个文件的「原文行 + 小写行」整表驻留内存，
/// 查询时逐行子串扫描。理由：
///   - Markdown 工作区千级文件总量在 ~10MB 量级，一次全表扫描 <50ms，足够输入即搜；
///   - CJK 文本没有空白分词，倒排索引对短语查询会退化成回表扫描，复杂度不值；
///   - 子串语义与 grep fallback 完全一致，索引/非索引路径的 Agent 结果可对齐。
/// 代价：内存约为文本总量 2 倍（原文 + 小写缓存），靠 512KB 单文件上限兜底。
///
/// 线程模型：actor。索引读写全部在 actor 内串行执行，IO 天然离开主线程；
/// 调用方（AppState / Agent repository）以 async 方式访问。
actor WorkspaceIndexService {

    /// 单文件索引上限：超过则跳过（大文件多为导出产物/数据文件，搜索价值低，
    /// 且全量驻留内存会放大常驻占用）。
    static let maxIndexedFileBytes = 512_000

    private struct IndexedFile {
        var relativePath: String
        var modificationDate: Date?
        var lines: [String]         // 原文行（供结果预览）
        var loweredLines: [String]  // 逐行小写缓存（大小写不敏感搜索免重复分配）
    }

    private var root: URL?
    private var files: [URL: IndexedFile] = [:]
    /// 防抖/代际标记：scheduleRefresh 连发时只保留最后一次；buildIndex/clear 会取消未执行的 refresh。
    private var refreshGeneration = 0

    // isReady 走独立锁盒而非 actor 隔离：Agent 搜索在「索引构建中」时需要零等待
    // 直接回退 grep 路径，不能排在 actor 队列里等整个构建完成。
    // let 属性允许 nonisolated 访问，无需 nonisolated(unsafe)。
    private final class ReadyFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var _value = false
        var value: Bool {
            get { lock.lock(); defer { lock.unlock() }; return _value }
            set { lock.lock(); _value = newValue; lock.unlock() }
        }
    }
    private let readyFlag = ReadyFlag()

    /// 首次全量构建是否已完成。构建中/已清空为 false。
    nonisolated var isReady: Bool { readyFlag.value }

    private func setReady(_ value: Bool) { readyFlag.value = value }

    /// 已索引文件数（诊断/测试用）。
    var indexedFileCount: Int { files.count }

    // MARK: - 全量构建

    /// 打开工作区时的全量重建。整个构建在 actor 内同步完成（IO 在后台执行），
    /// 期间到达的 search 调用会排队到构建结束后执行——UI 输入即搜自然得到最新结果。
    func buildIndex(root: URL) {
        refreshGeneration &+= 1   // 取消未执行的增量刷新
        self.root = root
        setReady(false)
        var newFiles: [URL: IndexedFile] = [:]
        for url in Self.enumerateWorkspaceFiles(root: root) {
            if let file = Self.loadFile(at: url, root: root) {
                newFiles[url] = file
            }
        }
        files = newFiles
        setReady(true)
    }

    /// 关闭/切换工作区时释放索引。
    func clear() {
        refreshGeneration &+= 1
        root = nil
        files = [:]
        setReady(false)
    }

    // MARK: - 增量更新

    /// FSEvents 变化入口（内部 300ms 防抖合并连续事件）。
    /// 采用「枚举 diff」而非逐事件路径：当前 FileWatcherService 回调不带路径信息，
    /// 且枚举 + modDate 比较对千级文件是毫秒级，简单且不会漏（移动/重命名天然覆盖）。
    func scheduleRefresh(root: URL) async {
        refreshGeneration &+= 1
        let generation = refreshGeneration
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard generation == refreshGeneration, !Task.isCancelled else { return }
        refresh(root: root)
    }

    /// 与磁盘做一次 diff：新文件入库、modDate 变化的重读、已删除的移除。
    private func refresh(root: URL) {
        guard self.root == root else { return }   // 只刷新当前工作区；切换走 buildIndex
        let diskURLs = Set(Self.enumerateWorkspaceFiles(root: root))
        files = files.filter { diskURLs.contains($0.key) }
        for url in diskURLs {
            let modDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate
            if let existing = files[url], existing.modificationDate == modDate { continue }
            // 新增/已修改：重读入库；变得不可读或超限时移出索引
            if let file = Self.loadFile(at: url, root: root) {
                files[url] = file
            } else {
                files.removeValue(forKey: url)
            }
        }
    }

    /// 单文件 upsert（Tab 保存 / Agent 写盘回调）。文件不在当前工作区内时忽略。
    func updateFile(at url: URL) {
        guard let root, url.path.hasPrefix(root.path + "/") else { return }
        guard FileManager.default.fileExists(atPath: url.path) else {
            files.removeValue(forKey: url)
            return
        }
        if let file = Self.loadFile(at: url, root: root) {
            files[url] = file
        } else {
            files.removeValue(forKey: url)
        }
    }

    /// 单文件移除（删除回调；FSEvents diff 也会兜住，此为即时路径）。
    func removeFile(at url: URL) {
        files.removeValue(forKey: url)
    }

    // MARK: - 搜索

    /// 子串搜索（大小写不敏感），语义与 grep -i 一致：query 整体作为短语匹配。
    /// - Parameters:
    ///   - extensions: 扩展名过滤（小写、不带点）；空数组 = 全部已索引文件。
    ///   - includeFileNames: 是否额外产出「文件名匹配」行（lineNumber == 0），UI 专用。
    ///   - maxTotal / maxPerFile: 结果上限（与 grep 路径的 --max-count=5 / 100 条对齐）。
    func search(
        query: String,
        extensions: [String] = [],
        includeFileNames: Bool = false,
        maxTotal: Int = 100,
        maxPerFile: Int = 5
    ) -> [WorkspaceSearchMatch] {
        let q = query.lowercased()
        guard !q.isEmpty else { return [] }
        let exts = Set(extensions.map { $0.lowercased() })
        var results: [WorkspaceSearchMatch] = []
        // 按相对路径排序遍历：结果顺序稳定，UI 与 Agent 输出可预期、可断言。
        for (url, file) in files.sorted(by: { $0.value.relativePath < $1.value.relativePath }) {
            guard results.count < maxTotal else { break }
            if !exts.isEmpty, !exts.contains(url.pathExtension.lowercased()) { continue }
            var perFile = 0
            if includeFileNames, url.lastPathComponent.lowercased().contains(q) {
                results.append(WorkspaceSearchMatch(relativePath: file.relativePath, lineNumber: 0, line: ""))
                perFile += 1
            }
            for (index, lowered) in file.loweredLines.enumerated() {
                guard perFile < maxPerFile, results.count < maxTotal else { break }
                if lowered.contains(q) {
                    results.append(WorkspaceSearchMatch(
                        relativePath: file.relativePath, lineNumber: index + 1, line: file.lines[index]))
                    perFile += 1
                }
            }
        }
        return results
    }

    // MARK: - 内部：枚举与加载

    /// 与 AgentFileRepository 同一套枚举规则（跳过 node_modules/.git 等噪音目录、隐藏文件）。
    private static func enumerateWorkspaceFiles(root: URL) -> [URL] {
        DefaultAgentFileRepository.enumerate(
            root: root, extensions: [], noiseDirectories: DefaultAgentFileRepository.noiseDirectories)
    }

    /// 读盘 + 解码 + 切行。返回 nil 的情形：超大小上限、iCloud 占位符（触发后台下载）、
    /// 读盘失败、无法按文本解码（二进制/未知编码——与 Agent 读盘路径同一套 TextFileDecoder）。
    private static func loadFile(at url: URL, root: URL) -> IndexedFile? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let size = values.fileSize, size <= maxIndexedFileBytes else { return nil }
        if UbiquitousFileHelper.isUbiquitousItemNotDownloaded(url) {
            UbiquitousFileHelper.startDownloadingIfNeeded(url)
            return nil
        }
        guard let data = try? Data(contentsOf: url) else { return nil }
        // 二进制判定：头部 8KB 内含 NUL 字节即跳过。UTF-16/32 文本天然含大量 0x00，
        // 因此带 BOM 的文件豁免，交给 TextFileDecoder 正常解码；
        // 无 BOM 的 UTF-16 会被误判为二进制——少见，取舍接受。
        let head = data.prefix(8192)
        let hasBOM = head.starts(with: [0xEF, 0xBB, 0xBF])          // UTF-8
            || head.starts(with: [0xFF, 0xFE]) || head.starts(with: [0xFE, 0xFF])  // UTF-16/32
        if !hasBOM, head.contains(0x00) { return nil }
        guard let text = TextFileDecoder.decode(data) else { return nil }
        let rootPath = root.path
        let relativePath = url.path.hasPrefix(rootPath + "/")
            ? String(url.path.dropFirst(rootPath.count + 1))
            : url.lastPathComponent
        let lines = text.components(separatedBy: .newlines)
        return IndexedFile(
            relativePath: relativePath,
            modificationDate: values.contentModificationDate,
            lines: lines,
            loweredLines: lines.map { $0.lowercased() }
        )
    }
}
