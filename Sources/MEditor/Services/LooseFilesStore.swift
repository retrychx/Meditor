import Foundation
import Observation

// MARK: - LooseFile

/// 不属于任何 Workspace 的散文件条目。
struct LooseFile: Identifiable, Equatable {
    let id: UUID
    let url: URL
    let source: Source
    let addedAt: Date

    var name: String { url.lastPathComponent }
    var directory: String { url.deletingLastPathComponent().path }

    enum Source: Equatable {
        case manual      // 用户直接从 Finder/拖拽打开
        case claude      // 来自 Claude Code 会话监听
    }

    init(url: URL, source: Source) {
        self.id       = UUID()
        self.url      = url
        self.source   = source
        self.addedAt  = Date()
    }
}

// MARK: - LooseFilesStore

/// 管理当前会话中打开的散文件列表（不跨 session 持久化）。
@MainActor
@Observable
final class LooseFilesStore {

    private(set) var files: [LooseFile] = []

    // MARK: - Mutations

    /// 添加一个散文件（如果已在列表中则不重复添加）。
    @discardableResult
    func add(_ url: URL, source: LooseFile.Source) -> LooseFile {
        if let existing = files.first(where: { $0.url == url }) {
            return existing
        }
        let file = LooseFile(url: url, source: source)
        files.insert(file, at: 0) // 最新在顶部
        return file
    }

    /// 移除指定散文件。
    func remove(_ id: UUID) {
        files.removeAll { $0.id == id }
    }

    func remove(_ url: URL) {
        files.removeAll { $0.url == url }
    }

    /// 判断某 URL 是否已在散文件列表中。
    func contains(_ url: URL) -> Bool {
        files.contains { $0.url == url }
    }

    /// 清空全部散文件。
    func clear() {
        files = []
    }
}
