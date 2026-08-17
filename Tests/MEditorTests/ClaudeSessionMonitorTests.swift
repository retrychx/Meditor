import XCTest
@testable import MEditor

// MARK: - ClaudeSessionMonitorTests
//
// 回归：旧实现把字节偏移在逐行解析之前提交，JSONL 尾部半行（Claude 正在写入中）
// 解析失败后被永久跳过（丢事件）。修复后只提交到最后一个完整换行处，
// 半行留到下轮重读——事件不丢、不重。

@MainActor
final class ClaudeSessionMonitorTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        // 用 realpath 拿真实路径：/var 在现代 macOS 上是 firmlink，
        // resolvingSymlinksInPath 不会解析它，但目录枚举器返回的是
        // 解析后的真实路径（/private/var/...），两边统一后路径比较才一致。
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-monitor-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var buf = [CChar](repeating: 0, count: Int(PATH_MAX))
        if realpath(dir.path, &buf) != nil {
            tempDir = URL(fileURLWithPath: String(cString: buf), isDirectory: true)
        } else {
            tempDir = dir
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Helpers

    /// 造一条 Write tool_use 的 assistant JSONL 行（目标文件必须真实存在，parseJSONL 排除假路径）
    private func writeToolLine(filePath: String) -> String {
        #"{"message":{"role":"assistant","content":[{"type":"tool_use","name":"Write","input":{"file_path":"\#(filePath)"}}]}}"#
    }

    private func createFile(_ name: String) -> URL {
        let url = tempDir.appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: Data())
        return url
    }

    private func append(_ data: Data, to url: URL) throws {
        let fh = try FileHandle(forWritingTo: url)
        try fh.seekToEnd()
        fh.write(data)
        try fh.close()
    }

    // MARK: - 半行分两次写入：不丢不重

    func test_scan_tailHalfLineNotCommitted_eventDeliveredOnceWhenLineCompletes() throws {
        let target  = createFile("note.md")
        let session = tempDir.appendingPathComponent("session.jsonl")
        let full = Data((writeToolLine(filePath: target.path) + "\n").utf8)
        let halfCount = full.count / 2
        let threeQuarterCount = full.count * 3 / 4

        // 第一次：只写入前半行（模拟 monitor 启动时 Claude 正在写）
        try full.prefix(halfCount).write(to: session)

        let monitor = ClaudeSessionMonitor()
        monitor.prescanExistingFiles(in: tempDir)   // 记录已有偏移（含半行）

        // 第二次：再追加一段，但仍无换行（半行还没写完）
        try append(full.subdata(in: halfCount..<threeQuarterCount), to: session)
        XCTAssertTrue(monitor.scanNewLines(in: tempDir).isEmpty,
                      "尾部半行不得产出事件，偏移也不得越过最后一个完整换行")

        // 第三次：写入剩余部分（含换行），行完整
        try append(full.suffix(from: threeQuarterCount), to: session)
        let events = monitor.scanNewLines(in: tempDir)
        XCTAssertEqual(events.count, 1, "半行补全后必须产出且只产出一次事件")
        XCTAssertEqual(events.first?.fileURL.path, target.path)
        XCTAssertEqual(events.first?.sessionURL.path, session.path)

        // 再扫：无新增字节，不得重复产出
        XCTAssertTrue(monitor.scanNewLines(in: tempDir).isEmpty,
                      "已提交的偏移不得重复产出事件")
    }

    // MARK: - 完整行 + 尾部半行混合：完整行先出，半行后补

    func test_scan_completeLinePlusHalfLine_emitsCompleteKeepsHalf() throws {
        let t1 = createFile("a.md")
        let t2 = createFile("b.md")
        let session = tempDir.appendingPathComponent("session.jsonl")

        let line2 = Data((writeToolLine(filePath: t2.path) + "\n").utf8)
        var part = Data((writeToolLine(filePath: t1.path) + "\n").utf8)
        part.append(line2.prefix(10))   // 第二行只写一半
        try part.write(to: session)

        let monitor = ClaudeSessionMonitor()

        // 第一行完整 → 立即产出；第二行半行 → 保留待下轮
        let events1 = monitor.scanNewLines(in: tempDir)
        XCTAssertEqual(events1.map { $0.fileURL.path }, [t1.path],
                       "完整行必须正常产出，尾部半行不得连带丢失")

        // 补全第二行
        try append(line2.suffix(from: 10), to: session)
        let events2 = monitor.scanNewLines(in: tempDir)
        XCTAssertEqual(events2.map { $0.fileURL.path }, [t2.path],
                       "补全后的半行必须产出，且前面的完整行不得重复")
    }
}
