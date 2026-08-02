import XCTest
@testable import MEditor

final class UbiquitousFileHelperTests: XCTestCase {

    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MEditorTests_\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
        super.tearDown()
    }

    private func createFile(_ name: String, content: String = "hello") -> URL {
        let url = tempDir.appendingPathComponent(name)
        try! content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // ubiquitous 下载状态无法在单测里模拟，这里只验证普通本地文件/无效路径的安全行为

    func test_isUbiquitousItemNotDownloaded_regularFile_returnsFalse() {
        let url = createFile("a.md")
        XCTAssertFalse(UbiquitousFileHelper.isUbiquitousItem(url))
        XCTAssertFalse(UbiquitousFileHelper.isUbiquitousItemNotDownloaded(url))
    }

    func test_isUbiquitousItemNotDownloaded_nonexistentPath_returnsFalse() {
        let url = tempDir.appendingPathComponent("nope.md")
        XCTAssertFalse(UbiquitousFileHelper.isUbiquitousItem(url))
        XCTAssertFalse(UbiquitousFileHelper.isUbiquitousItemNotDownloaded(url))
    }

    func test_startDownloadingIfNeeded_regularFile_isNoOp() {
        // 普通文件不应触发任何下载行为，也不应抛错或崩溃
        let url = createFile("b.md")
        UbiquitousFileHelper.startDownloadingIfNeeded(url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func test_textFileDecoder_regularFile_readsNormally() throws {
        // 确认 iCloud 检查不影响普通文件的正常读取
        let url = createFile("c.md", content: "# 你好")
        let content = try TextFileDecoder.decode(contentsOf: url)
        XCTAssertEqual(content, "# 你好")
    }

    func test_agentContextError_fileNotDownloaded_hasReadableMessage() {
        let err = AgentContextError.fileNotDownloaded("x.md")
        XCTAssertTrue(err.errorDescription?.contains("x.md") == true)
        XCTAssertTrue(err.errorDescription?.contains("iCloud") == true)
    }
}
