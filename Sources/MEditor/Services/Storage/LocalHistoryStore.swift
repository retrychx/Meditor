import Foundation
import CryptoKit

// MARK: - HistorySnapshot

/// 一份本地历史快照的元信息。快照内容按原文件扩展名存储在
/// `Application Support/MEditor/History/<pathHash>/` 下。
struct HistorySnapshot: Identifiable, Equatable {
    let url: URL
    let date: Date
    let size: Int64

    var id: String { url.lastPathComponent }
}

// MARK: - LocalHistoryStore

/// 本地历史快照存取：覆盖「用户自己手滑改坏文件」的场景（agent run 回滚由
/// AgentRunCheckpoint 负责，与本机制互补）。
///
/// - 每次保存落一份快照，按文件路径 SHA-256 前缀分桶组织；
/// - 保留策略为时间分层稀释（类 macOS Versions），按快照文件 modDate 判定：
///   1 小时内全留 → 24 小时内每小时留最新一份 → `maxSnapshotAge`（30 天）内
///   每天留最新一份，超过 30 天删除；另加每文件硬上限 `maxSnapshotsPerFile` 防爆。
///   写入时清理本桶，启动时 `pruneAll()` 惰性清理全部（空桶目录一并删除）；
/// - 大文件保护：超过 `maxSnapshotFileSize` 的内容跳过快照；
/// - 与最新快照内容相同则跳过，避免连续保存产生重复副本。
///
/// 线程安全：所有方法均为无共享状态的文件操作，可在后台线程调用；
/// 对同一文件的并发写由原子写 + 唯一文件名兜底（最坏多一份快照，随后被清理）。
final class LocalHistoryStore {

    /// 每文件快照硬上限：防爆兜底，正常分层稀释远达不到这个数。
    static let maxSnapshotsPerFile = 100
    static let maxSnapshotAge: TimeInterval = 30 * 24 * 60 * 60
    static let maxSnapshotFileSize = 2 * 1024 * 1024
    /// 最近窗口：该时长内的快照全部保留（自动保存高频落快照不被稀释）。
    static let recentWindow: TimeInterval = 60 * 60
    /// 小时分层窗口：recentWindow ~ 该时长之间，每个自然小时保留最新一份。
    static let hourlyWindow: TimeInterval = 24 * 60 * 60

    private let baseDir: URL
    private let fm = FileManager.default

    init(baseDir: URL? = nil) {
        let base = baseDir
            ?? FileManager.default.firstURL(for: .applicationSupportDirectory)
        self.baseDir = base.appendingPathComponent("MEditor/History", isDirectory: true)
    }

    // MARK: - 路径组织

    /// 文件路径 → 桶目录名（SHA-256 前 8 字节 hex，稳定且避免路径字符问题）。
    static func bucketName(for fileURL: URL) -> String {
        let path = fileURL.standardizedFileURL.path
        let digest = SHA256.hash(data: Data(path.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    func bucketURL(for fileURL: URL) -> URL {
        baseDir.appendingPathComponent(Self.bucketName(for: fileURL), isDirectory: true)
    }

    // MARK: - 写入

    /// 落一份快照。返回 nil 的情况：内容超过大小上限，或与最新快照完全相同。
    @discardableResult
    func recordSnapshot(of fileURL: URL, content: String, now: Date = Date()) throws -> HistorySnapshot? {
        guard content.utf8.count <= Self.maxSnapshotFileSize else { return nil }

        let bucket = bucketURL(for: fileURL)
        if let newest = snapshots(for: fileURL).first,
           let existing = try? String(contentsOf: newest.url, encoding: .utf8),
           existing == content {
            return nil
        }

        try fm.createDirectory(at: bucket, withIntermediateDirectories: true)
        let ext = fileURL.pathExtension
        let name = Self.snapshotName(date: now, suffix: Self.randomSuffix(), ext: ext)
        let url = uniqueURL(in: bucket, filename: name)
        try content.write(to: url, atomically: true, encoding: .utf8)

        pruneBucket(bucket, now: now)
        return makeSnapshot(url: url)
    }

    // MARK: - 读取

    /// 某文件的全部快照，新的在前（文件名时间戳字典序即时间序）。
    func snapshots(for fileURL: URL) -> [HistorySnapshot] {
        let bucket = bucketURL(for: fileURL)
        guard let files = try? fm.contentsOfDirectory(
            at: bucket, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
        ) else { return [] }
        return files
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .compactMap(makeSnapshot)
    }

    func readSnapshot(_ snapshot: HistorySnapshot) throws -> String {
        try String(contentsOf: snapshot.url, encoding: .utf8)
    }

    // MARK: - 清理

    /// 启动时惰性清理：遍历所有桶，应用时间分层 + 硬上限保留策略；
    /// 桶清空后删除目录，避免空桶堆积。
    func pruneAll(now: Date = Date()) {
        guard let buckets = try? fm.contentsOfDirectory(
            at: baseDir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else { return }
        for bucket in buckets {
            pruneBucket(bucket, now: now)
            if let remaining = try? fm.contentsOfDirectory(atPath: bucket.path), remaining.isEmpty {
                try? fm.removeItem(at: bucket)
            }
        }
    }

    /// 时间分层稀释：1 小时内全留 → 24 小时内每小时留最新一份 → 30 天内每天留
    /// 最新一份 → 过期删除；任何情况下都不超过 maxSnapshotsPerFile 份。
    /// 分层按 modDate 判定；同层分组用自然小时/自然日（本地时区）。
    private func pruneBucket(_ bucket: URL, now: Date) {
        guard let files = try? fm.contentsOfDirectory(
            at: bucket, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        // 新的在前；modDate 相同时按文件名（内嵌时间戳）次序兜底，保证确定性。
        let items: [(url: URL, date: Date)] = files.compactMap { url in
            guard let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate else { return nil }
            return (url, date)
        }.sorted {
            if $0.date != $1.date { return $0.date > $1.date }
            return $0.url.lastPathComponent > $1.url.lastPathComponent
        }

        var kept = 0
        var seenHours = Set<String>()
        var seenDays = Set<String>()
        for item in items {
            let age = now.timeIntervalSince(item.date)
            var keep = true
            if age > Self.maxSnapshotAge || kept >= Self.maxSnapshotsPerFile {
                keep = false
            } else if age >= Self.hourlyWindow {
                keep = seenDays.insert(Self.dayBucketFormatter.string(from: item.date)).inserted
            } else if age >= Self.recentWindow {
                keep = seenHours.insert(Self.hourBucketFormatter.string(from: item.date)).inserted
            }
            if keep {
                kept += 1
            } else {
                try? fm.removeItem(at: item.url)
            }
        }
    }

    // MARK: - 命名

    /// 快照文件名：yyyyMMdd-HHmmss-xxxx.<原扩展名>（字典序 = 时间序）。
    static func snapshotName(date: Date, suffix: String, ext: String) -> String {
        let base = "\(timestampFormatter.string(from: date))-\(suffix)"
        return ext.isEmpty ? base : "\(base).\(ext)"
    }

    static func randomSuffix() -> String {
        String(format: "%04x", Int.random(in: 0...0xFFFF))
    }

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()

    /// 小时分层分桶键（自然小时，本地时区）。
    private static let hourBucketFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMddHH"
        return f
    }()

    /// 天分层分桶键（自然日，本地时区）。
    private static let dayBucketFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd"
        return f
    }()

    /// 同秒同名冲突时追加 -2、-3…
    private func uniqueURL(in dir: URL, filename: String) -> URL {
        var candidate = dir.appendingPathComponent(filename)
        guard fm.fileExists(atPath: candidate.path) else { return candidate }
        let ns = filename as NSString
        let ext = ns.pathExtension
        let base = ns.deletingPathExtension
        var i = 2
        while true {
            let name = ext.isEmpty ? "\(base)-\(i)" : "\(base)-\(i).\(ext)"
            candidate = dir.appendingPathComponent(name)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            i += 1
        }
    }

    private func makeSnapshot(url: URL) -> HistorySnapshot? {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        return HistorySnapshot(
            url: url,
            date: values?.contentModificationDate ?? .distantPast,
            size: Int64(values?.fileSize ?? 0)
        )
    }
}
