import XCTest
@testable import MEditor

final class LocalHistoryStoreTests: XCTestCase {

    var tempDir: URL!
    var store: LocalHistoryStore!
    var fileURL: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MEditorTests_\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = LocalHistoryStore(baseDir: tempDir.appendingPathComponent("appSupport"))
        fileURL = tempDir.appendingPathComponent("docs/note.md")
        try! FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! "v0".write(to: fileURL, atomically: true, encoding: .utf8)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        store = nil
        fileURL = nil
        tempDir = nil
        super.tearDown()
    }

    // MARK: - bucketName

    func test_bucketName_stableAndDistinct() {
        let a = LocalHistoryStore.bucketName(for: fileURL)
        let b = LocalHistoryStore.bucketName(for: fileURL)
        let other = LocalHistoryStore.bucketName(
            for: tempDir.appendingPathComponent("docs/other.md"))
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, other)
        XCTAssertEqual(a.count, 16)
        XCTAssertNotNil(a.range(of: #"^[0-9a-f]{16}$"#, options: .regularExpression))
    }

    // MARK: - record / list / read

    func test_recordSnapshot_createsReadableSnapshot() throws {
        let snapshot = try XCTUnwrap(store.recordSnapshot(of: fileURL, content: "v1"))

        // 保留原扩展名，落在该文件的桶目录下
        XCTAssertEqual(snapshot.url.pathExtension, "md")
        XCTAssertEqual(snapshot.url.deletingLastPathComponent().lastPathComponent,
                       LocalHistoryStore.bucketName(for: fileURL))
        XCTAssertEqual(try store.readSnapshot(snapshot), "v1")
        XCTAssertEqual(snapshot.size, Int64("v1".utf8.count))
    }

    func test_snapshots_newestFirst() throws {
        let day: TimeInterval = 24 * 3600
        try store.recordSnapshot(of: fileURL, content: "old", now: Date().addingTimeInterval(-2 * day))
        try store.recordSnapshot(of: fileURL, content: "mid", now: Date().addingTimeInterval(-day))
        try store.recordSnapshot(of: fileURL, content: "new", now: Date())

        let contents = store.snapshots(for: fileURL).map { try! store.readSnapshot($0) }
        XCTAssertEqual(contents, ["new", "mid", "old"])
    }

    func test_recordSnapshot_identicalToNewest_isSkipped() throws {
        try store.recordSnapshot(of: fileURL, content: "same")
        let second = try store.recordSnapshot(of: fileURL, content: "same")
        XCTAssertNil(second)
        XCTAssertEqual(store.snapshots(for: fileURL).count, 1)
    }

    func test_recordSnapshot_oversized_isSkipped() throws {
        let big = String(repeating: "x", count: LocalHistoryStore.maxSnapshotFileSize + 1)
        let result = try store.recordSnapshot(of: fileURL, content: big)
        XCTAssertNil(result)
        XCTAssertTrue(store.snapshots(for: fileURL).isEmpty)
    }

    func test_snapshots_isolatedPerFile() throws {
        let other = tempDir.appendingPathComponent("docs/other.md")
        try store.recordSnapshot(of: fileURL, content: "a")
        try store.recordSnapshot(of: other, content: "b")

        XCTAssertEqual(store.snapshots(for: fileURL).count, 1)
        XCTAssertEqual(store.snapshots(for: other).count, 1)
        XCTAssertEqual(try store.readSnapshot(store.snapshots(for: fileURL)[0]), "a")
        XCTAssertEqual(try store.readSnapshot(store.snapshots(for: other)[0]), "b")
    }

    // MARK: - 保留策略

    func test_recordSnapshot_prunesBeyondMaxCount() throws {
        // 硬上限兜底：recentWindow 内分层不稀释，只能靠 maxSnapshotsPerFile 截断
        for i in 0..<(LocalHistoryStore.maxSnapshotsPerFile + 5) {
            try store.recordSnapshot(of: fileURL, content: "v\(i)",
                                     now: Date().addingTimeInterval(TimeInterval(i)))
        }
        let snapshots = store.snapshots(for: fileURL)
        XCTAssertEqual(snapshots.count, LocalHistoryStore.maxSnapshotsPerFile)
        // 最新的保留
        XCTAssertEqual(try store.readSnapshot(snapshots[0]), "v\(LocalHistoryStore.maxSnapshotsPerFile + 4)")
    }

    func test_recordSnapshot_prunesExpired() throws {
        let expired = Date().addingTimeInterval(-(LocalHistoryStore.maxSnapshotAge + 3600))
        try store.recordSnapshot(of: fileURL, content: "ancient", now: expired)
        // 旧快照的文件修改时间也要拨回过去，否则按 modDate 判断不过期
        let bucket = store.bucketURL(for: fileURL)
        let old = try FileManager.default.contentsOfDirectory(atPath: bucket.path)
        for name in old {
            try FileManager.default.setAttributes(
                [.modificationDate: expired],
                ofItemAtPath: bucket.appendingPathComponent(name).path)
        }

        try store.recordSnapshot(of: fileURL, content: "fresh", now: Date())

        let contents = store.snapshots(for: fileURL).map { try! store.readSnapshot($0) }
        XCTAssertEqual(contents, ["fresh"])
    }

    func test_pruneAll_cleansAcrossBuckets() throws {
        let expired = Date().addingTimeInterval(-(LocalHistoryStore.maxSnapshotAge + 3600))
        let other = tempDir.appendingPathComponent("docs/other.md")
        for url in [fileURL!, other] {
            try store.recordSnapshot(of: url, content: "old", now: expired)
            let bucket = store.bucketURL(for: url)
            for name in try FileManager.default.contentsOfDirectory(atPath: bucket.path) {
                try FileManager.default.setAttributes(
                    [.modificationDate: expired],
                    ofItemAtPath: bucket.appendingPathComponent(name).path)
            }
        }
        store.pruneAll()
        XCTAssertTrue(store.snapshots(for: fileURL).isEmpty)
        XCTAssertTrue(store.snapshots(for: other).isEmpty)
    }

    // MARK: - 时间分层稀释（类 macOS Versions）

    /// 直接写一份指定 modDate 的原始快照（绕过 recordSnapshot 的去重/大小检查），
    /// 用于构造落在不同历史层级的快照。
    private func writeRawSnapshot(_ content: String, modDate: Date) throws {
        let bucket = store.bucketURL(for: fileURL)
        try FileManager.default.createDirectory(at: bucket, withIntermediateDirectories: true)
        let name = LocalHistoryStore.snapshotName(
            date: modDate, suffix: String(UUID().uuidString.prefix(4)).lowercased(), ext: "md")
        let url = bucket.appendingPathComponent(name)
        try content.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: modDate], ofItemAtPath: url.path)
    }

    private func snapshotContents() -> [String] {
        store.snapshots(for: fileURL).map { try! store.readSnapshot($0) }
    }

    func test_prune_recentWindowKeepsEverything() throws {
        let now = Date()
        // 1 小时内高频快照（模拟自动保存 debounce 落盘）：一份都不能少
        for i in 0..<10 {
            try writeRawSnapshot("r\(i)", modDate: now.addingTimeInterval(TimeInterval(-i * 60)))
        }
        store.pruneAll(now: now)
        XCTAssertEqual(snapshotContents().count, 10)
    }

    func test_prune_hourlyTierKeepsNewestPerHour() throws {
        let now = Date()
        // 取 2 小时前所在的自然小时，保证整段都落在「1~24 小时」分层内
        let hour = Calendar.current.dateInterval(
            of: .hour, for: now.addingTimeInterval(-2 * 3600))!
        try writeRawSnapshot("h-old", modDate: hour.start.addingTimeInterval(60))
        try writeRawSnapshot("h-mid", modDate: hour.start.addingTimeInterval(120))
        try writeRawSnapshot("h-new", modDate: hour.start.addingTimeInterval(180))
        // 上一个自然小时 1 份：属于别的桶，不受本小时稀释影响
        try writeRawSnapshot("prev-hour", modDate: hour.start.addingTimeInterval(-60))

        store.pruneAll(now: now)
        XCTAssertEqual(Set(snapshotContents()), ["h-new", "prev-hour"])
    }

    func test_prune_dailyTierKeepsNewestPerDay() throws {
        let now = Date()
        // 3 天前所在的自然日，保证整段都落在「1~30 天」分层内
        let day = Calendar.current.dateInterval(
            of: .day, for: now.addingTimeInterval(-3 * 86400))!
        try writeRawSnapshot("d-old", modDate: day.start.addingTimeInterval(3600))
        try writeRawSnapshot("d-mid", modDate: day.start.addingTimeInterval(2 * 3600))
        try writeRawSnapshot("d-new", modDate: day.start.addingTimeInterval(3 * 3600))
        try writeRawSnapshot("prev-day", modDate: day.start.addingTimeInterval(-3600))

        store.pruneAll(now: now)
        XCTAssertEqual(Set(snapshotContents()), ["d-new", "prev-day"])
    }

    func test_pruneAll_removesEmptyBucketDirectory() throws {
        let expired = Date().addingTimeInterval(-(LocalHistoryStore.maxSnapshotAge + 3600))
        try writeRawSnapshot("old", modDate: expired)
        let bucket = store.bucketURL(for: fileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: bucket.path))

        store.pruneAll()
        XCTAssertTrue(store.snapshots(for: fileURL).isEmpty)
        // 桶清空后目录一并删除
        XCTAssertFalse(FileManager.default.fileExists(atPath: bucket.path))
    }

    // MARK: - 快照命名

    func test_snapshotName_keepsExtensionAndSortable() {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 1; comps.day = 2; comps.hour = 3; comps.minute = 4; comps.second = 5
        let date = Calendar(identifier: .gregorian).date(from: comps)!
        let name = LocalHistoryStore.snapshotName(date: date, suffix: "ab12", ext: "md")
        XCTAssertTrue(name.hasSuffix("-ab12.md"))
        XCTAssertNotNil(name.range(of: #"^\d{8}-\d{6}-"#, options: .regularExpression))
        // 无扩展名文件
        XCTAssertEqual(LocalHistoryStore.snapshotName(date: date, suffix: "ab12", ext: "").hasSuffix(".md"), false)
    }
}
