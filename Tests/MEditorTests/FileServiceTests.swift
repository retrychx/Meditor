import XCTest
@testable import MEditor

final class FileServiceTests: XCTestCase {

    var tempDir: URL!
    var service: FileService!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MEditorTests_\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        service = FileService()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        service = nil
        tempDir = nil
        super.tearDown()
    }

    // MARK: - Helpers

    @discardableResult
    func createFile(_ name: String, content: String = "") -> URL {
        let url = tempDir.appendingPathComponent(name)
        try! content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @discardableResult
    func createDir(_ name: String) -> URL {
        let url = tempDir.appendingPathComponent(name)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - loadImmediateChildren

    func test_loadImmediateChildren_returnsFilesAndDirs() {
        createFile("readme.md")
        createFile("index.html")
        createDir("images")

        let items = service.loadImmediateChildren(of: tempDir)
        let names = Set(items.map(\.name))
        XCTAssertTrue(names.contains("readme.md"))
        XCTAssertTrue(names.contains("index.html"))
        XCTAssertTrue(names.contains("images"))
    }

    func test_loadImmediateChildren_filtersUnsupportedExtensions() {
        createFile("doc.md")
        createFile("script.js")
        createFile("style.css")

        let items = service.loadImmediateChildren(of: tempDir)
        let names = items.map(\.name)
        XCTAssertTrue(names.contains("doc.md"))
        XCTAssertFalse(names.contains("script.js"))
        XCTAssertFalse(names.contains("style.css"))
    }

    func test_loadImmediateChildren_directoriesAlwaysAppear() {
        createDir("node_modules")
        createFile("readme.md")

        let items = service.loadImmediateChildren(of: tempDir)
        let dirNames = items.filter(\.isDirectory).map(\.name)
        XCTAssertTrue(dirNames.contains("node_modules"))
    }

    func test_loadImmediateChildren_skipsHiddenFiles() {
        createFile(".hidden.md")
        createFile("visible.md")

        let items = service.loadImmediateChildren(of: tempDir)
        let names = items.map(\.name)
        XCTAssertFalse(names.contains(".hidden.md"))
        XCTAssertTrue(names.contains("visible.md"))
    }

    func test_loadImmediateChildren_emptyDir() {
        let items = service.loadImmediateChildren(of: tempDir)
        XCTAssertTrue(items.isEmpty)
    }

    // MARK: - Sort order

    func test_loadImmediateChildren_directoriesFirst() {
        createDir("zassets")
        createFile("aaa.md")

        let items = service.loadImmediateChildren(of: tempDir)
        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items[0].isDirectory)  // dirs first
        XCTAssertFalse(items[1].isDirectory)
    }

    func test_loadImmediateChildren_alphabeticalWithinTypes() {
        createFile("zebra.md")
        createFile("alpha.md")
        createDir("beta")
        createDir("aaa")

        let items = service.loadImmediateChildren(of: tempDir)
        let names = items.map(\.name)

        // dirs first: aaa, beta
        let dirs = items.filter(\.isDirectory)
        XCTAssertEqual(dirs[0].name, "aaa")
        XCTAssertEqual(dirs[1].name, "beta")

        // files after: alpha, zebra
        let files = items.filter { !$0.isDirectory }
        XCTAssertEqual(files[0].name, "alpha.md")
        XCTAssertEqual(files[1].name, "zebra.md")
    }

    func test_loadImmediateChildren_caseInsensitiveSort() {
        createFile("Zebra.md")
        createFile("alpha.md")

        let items = service.loadImmediateChildren(of: tempDir)
        let names = items.map(\.name)
        XCTAssertEqual(names[0], "alpha.md")
        XCTAssertEqual(names[1], "Zebra.md")
    }

    // MARK: - loadChildren

    func test_loadChildren_setsChildrenOnItem() {
        createDir("sub")
        createFile("sub/a.md")
        createFile("sub/b.html")

        let parent = FileItem(url: tempDir.appendingPathComponent("sub"), isDirectory: true)
        let children = service.loadChildren(for: parent)

        XCTAssertNotNil(parent.children)
        XCTAssertEqual(children.count, 2)
        let names = children.map(\.name)
        XCTAssertTrue(names.contains("a.md"))
        XCTAssertTrue(names.contains("b.html"))
    }

    // MARK: - readFile / writeFile

    func test_readFile_success() throws {
        let url = createFile("hello.md", content: "# Hello")
        let content = try service.readFile(at: url)
        XCTAssertEqual(content, "# Hello")
    }

    func test_readFile_nonexistent_throws() {
        let url = tempDir.appendingPathComponent("nope.md")
        XCTAssertThrowsError(try service.readFile(at: url))
    }

    func test_writeFile_createsFile() throws {
        let url = tempDir.appendingPathComponent("output.md")
        try service.writeFile(at: url, content: "# Written")
        let readBack = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(readBack, "# Written")
    }

    func test_writeFile_overwrites() throws {
        let url = createFile("overwrite.md", content: "# Old")
        try service.writeFile(at: url, content: "# New")
        let readBack = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(readBack, "# New")
    }

    func test_loadImmediateChildren_nonexistentDir_returnsEmpty() {
        let badURL = URL(fileURLWithPath: "/nonexistent_path_xyz")
        let items = service.loadImmediateChildren(of: badURL)
        XCTAssertTrue(items.isEmpty)
    }
}
