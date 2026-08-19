import XCTest
@testable import MEditor

final class ImageAssetServiceTests: XCTestCase {

    var tempDir: URL!
    var fallbackBase: URL!
    var service: ImageAssetService!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MEditorTests_\(UUID().uuidString)")
        fallbackBase = tempDir.appendingPathComponent("fallback")
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        service = ImageAssetService(fallbackBaseDir: fallbackBase)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        service = nil
        tempDir = nil
        fallbackBase = nil
        super.tearDown()
    }

    // MARK: - Helpers

    @discardableResult
    func createFile(_ relativePath: String, content: String = "") -> URL {
        let url = tempDir.appendingPathComponent(relativePath)
        try! FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - timestampedBaseName / uniqueURL

    func test_timestampedBaseName_format() {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 8; comps.day = 19
        comps.hour = 1; comps.minute = 25; comps.second = 31
        let date = Calendar(identifier: .gregorian).date(from: comps)!
        let name = ImageAssetService.timestampedBaseName(date: date, suffix: "a1b2")
        // 时区无关断言：长度与结构稳定（yyyyMMdd-HHmmss-xxxx）
        let pattern = #"^\d{8}-\d{6}-a1b2$"#
        XCTAssertNotNil(name.range(of: pattern, options: .regularExpression))
    }

    func test_uniqueURL_noCollision_returnsOriginal() {
        let url = ImageAssetService.uniqueURL(in: tempDir, filename: "a.png")
        XCTAssertEqual(url.lastPathComponent, "a.png")
    }

    func test_uniqueURL_collision_appendsCounter() {
        createFile("a.png")
        createFile("a-2.png")
        let url = ImageAssetService.uniqueURL(in: tempDir, filename: "a.png")
        XCTAssertEqual(url.lastPathComponent, "a-3.png")
    }

    // MARK: - relativePath

    func test_relativePath_sameDirectory() {
        let base = tempDir.appendingPathComponent("docs")
        let target = tempDir.appendingPathComponent("docs/assets/x.png")
        XCTAssertEqual(ImageAssetService.relativePath(from: base, to: target), "assets/x.png")
    }

    func test_relativePath_siblingDirectory_usesDotDot() {
        let base = tempDir.appendingPathComponent("docs")
        let target = tempDir.appendingPathComponent("assets/x.png")
        XCTAssertEqual(ImageAssetService.relativePath(from: base, to: target), "../assets/x.png")
    }

    func test_relativePath_unrelated_roots() {
        let base = tempDir.appendingPathComponent("a/b")
        let target = tempDir.appendingPathComponent("c/x.png")
        XCTAssertEqual(ImageAssetService.relativePath(from: base, to: target), "../../c/x.png")
    }

    // MARK: - escapedPath / markdownReference

    func test_escapedPath_encodesSpacesAndParens() {
        XCTAssertEqual(ImageAssetService.escapedPath("assets/my pic(1).png"),
                       "assets/my%20pic%281%29.png")
    }

    func test_escapedPath_encodesNonASCII() {
        let escaped = ImageAssetService.escapedPath("assets/截图.png")
        XCTAssertFalse(escaped.contains("截图"))
        XCTAssertTrue(escaped.hasPrefix("assets/"))
        XCTAssertTrue(escaped.hasSuffix(".png"))
    }

    func test_markdownReference_stripsBracketsFromAlt() {
        XCTAssertEqual(ImageAssetService.markdownReference(alt: "a[1]b", path: "assets/x.png"),
                       "![a1b](assets/x.png)")
    }

    // MARK: - savePastedImage

    func test_savePastedImage_writesToDocAssetsWithRelativeReference() throws {
        let doc = createFile("docs/note.md", content: "hello")
        let data = Data([0x89, 0x50, 0x4E, 0x47])  // PNG magic bytes 占位

        let result = try service.savePastedImage(data: data, fileExtension: "png", documentURL: doc)

        // 落在文档同级 assets/，引用是相对路径
        let expectedDir = tempDir.appendingPathComponent("docs/assets")
        XCTAssertEqual(result.fileURL.deletingLastPathComponent().standardizedFileURL,
                       expectedDir.standardizedFileURL)
        XCTAssertEqual(try Data(contentsOf: result.fileURL), data)
        XCTAssertTrue(result.markdown.hasPrefix("!["))
        XCTAssertTrue(result.markdown.contains("](assets/"))
        XCTAssertTrue(result.markdown.hasSuffix(".png)"))
    }

    func test_savePastedImage_existingAssetsDir_reusedNotRecreated() throws {
        let doc = createFile("note.md")
        try FileManager.default.createDirectory(
            at: tempDir.appendingPathComponent("assets"), withIntermediateDirectories: true)
        let r = try service.savePastedImage(data: Data([1]), fileExtension: "png", documentURL: doc)
        XCTAssertEqual(r.fileURL.deletingLastPathComponent().lastPathComponent, "assets")
        XCTAssertTrue(r.markdown.contains("](assets/"))
    }

    func test_savePastedImage_readonlyDocDir_fallsBackToAppSupport() throws {
        let docDir = tempDir.appendingPathComponent("readonly")
        let doc = createFile("readonly/note.md")
        // 只读目录：assets 子目录创建失败 → 走兜底目录，引用为绝对路径
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: docDir.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: docDir.path) }

        let result = try service.savePastedImage(data: Data([1, 2, 3]), fileExtension: "png", documentURL: doc)

        XCTAssertTrue(result.fileURL.path.hasPrefix(fallbackBase.appendingPathComponent("MEditor/PastedImages").path))
        XCTAssertTrue(result.markdown.contains(result.fileURL.lastPathComponent))
        XCTAssertTrue(result.markdown.contains("]("), "markdown 引用应包含路径")
    }

    // MARK: - referenceForDroppedFile

    func test_droppedFileInsideWorkspace_referencedWithoutCopy() throws {
        let doc = createFile("docs/note.md")
        let image = createFile("images/pic.png", content: "png-bytes")
        let root = tempDir

        let result = try service.referenceForDroppedFile(image, documentURL: doc, workspaceRoot: root)

        // 不复制：引用原文件本身；相对路径带 ../
        XCTAssertEqual(result.fileURL.standardizedFileURL, image.standardizedFileURL)
        XCTAssertEqual(result.markdown, "![pic](../images/pic.png)")
    }

    func test_droppedFileOutsideWorkspace_copiedIntoAssets() throws {
        let doc = createFile("docs/note.md")
        // 工作区外的文件（放 tempDir 外不行，用另一棵目录树模拟）
        let outsideRoot = tempDir.appendingPathComponent("outside")
        let image = tempDir.appendingPathComponent("outside/my pic.png")
        try! FileManager.default.createDirectory(at: outsideRoot, withIntermediateDirectories: true)
        try! Data([9, 9]).write(to: image)
        let workspace = tempDir.appendingPathComponent("docs")  // 工作区只含 docs/

        let result = try service.referenceForDroppedFile(image, documentURL: doc, workspaceRoot: workspace)

        let expected = tempDir.appendingPathComponent("docs/assets/my pic.png")
        XCTAssertEqual(result.fileURL.standardizedFileURL, expected.standardizedFileURL)
        XCTAssertEqual(try Data(contentsOf: expected), Data([9, 9]))
        XCTAssertEqual(result.markdown, "![my pic](assets/my%20pic.png)")
    }

    func test_droppedFile_noWorkspace_copiedIntoAssets() throws {
        let doc = createFile("docs/note.md")
        let image = createFile("docs/other.png", content: "x")

        let result = try service.referenceForDroppedFile(image, documentURL: doc, workspaceRoot: nil)

        XCTAssertEqual(result.fileURL.deletingLastPathComponent().lastPathComponent, "assets")
        XCTAssertTrue(result.markdown.hasPrefix("![other](assets/other"))
    }
}
