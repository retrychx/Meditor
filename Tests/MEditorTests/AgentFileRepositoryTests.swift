import XCTest
@testable import MEditor

/// DefaultAgentFileRepository 的磁盘 IO 测试：临时目录 + UUID 隔离。
/// 覆盖路径解析、同名歧义、多编码读取、高低级写、搜索（grep 快路径 + swiftSearch 慢路径）。
/// 注意：repository 层本身不做工作区 confinement（那是 AgentContext.validateWriteTarget
/// 的职责，已由 AgentWriteConfinementTests 覆盖），这里验证的是裸路径解析行为。
final class AgentFileRepositoryTests: XCTestCase {

    var tempDir: URL!
    var repo: DefaultAgentFileRepository!

    override func setUp() {
        super.setUp()
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("MEditorRepoTests_\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        // 枚举器返回 realpath 形式的 URL（/var → /private/var）；统一基准便于 URL 相等比较
        var buf = [CChar](repeating: 0, count: Int(PATH_MAX))
        realpath(base.path, &buf)
        tempDir = URL(fileURLWithPath: String(cString: buf))
        let root = tempDir!
        repo = DefaultAgentFileRepository { root }
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        repo = nil
        tempDir = nil
        super.tearDown()
    }

    // MARK: - Helpers

    @discardableResult
    func createFile(_ name: String, content: String = "") -> URL {
        let url = tempDir.appendingPathComponent(name)
        try! FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @discardableResult
    func createDir(_ name: String) -> URL {
        let url = tempDir.appendingPathComponent(name)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - resolveURL

    func testResolveURL_absolutePath_passesThrough() {
        let url = repo.resolveURL("/tmp/whatever.md")
        XCTAssertEqual(url.path, "/tmp/whatever.md")
    }

    func testResolveURL_relativePath_joinsWorkspaceRoot() {
        let url = repo.resolveURL("docs/intro.md")
        XCTAssertEqual(url.path, tempDir.appendingPathComponent("docs/intro.md").path)
    }

    func testResolveURL_noWorkspace_fallsBackToHome() {
        let noRoot = DefaultAgentFileRepository { nil }
        let url = noRoot.resolveURL("notes.md")
        XCTAssertEqual(url.path, URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("notes.md").path)
    }

    // MARK: - resolveFile

    func testResolveFile_absoluteExisting_found() {
        let file = createFile("abs.md", content: "x")
        switch repo.resolveFile(file.path) {
        case .found(let url): XCTAssertEqual(url, file.standardizedFileURL)
        default: XCTFail("绝对路径存在的文件应 .found")
        }
    }

    func testResolveFile_absoluteMissing_notFound() {
        switch repo.resolveFile(tempDir.appendingPathComponent("nope.md").path) {
        case .notFound: break
        default: XCTFail("绝对路径不存在应 .notFound")
        }
    }

    func testResolveFile_relativeSubpath_found() {
        let file = createFile("docs/intro.md", content: "x")
        switch repo.resolveFile("docs/intro.md") {
        case .found(let url): XCTAssertEqual(url, file.standardizedFileURL)
        default: XCTFail("带 / 的相对路径应直接解析到工作区内文件")
        }
    }

    func testResolveFile_bareNameUnique_found() {
        let file = createFile("deep/nested/unique.md", content: "x")
        switch repo.resolveFile("unique.md") {
        // 同名搜索结果来自枚举器（realpath 形式），不要与 standardizedFileURL 混比
        case .found(let url): XCTAssertEqual(url, file)
        default: XCTFail("唯一同名文件应 .found")
        }
    }

    func testResolveFile_bareNameMissing_notFound() {
        createFile("other.md")
        switch repo.resolveFile("ghost.md") {
        case .notFound: break
        default: XCTFail("应 .notFound")
        }
    }

    func testResolveFile_bareNameDuplicate_ambiguousSortedByDepthThenAlpha() {
        let deep    = createFile("a/b/dup.md")
        let shallow = createFile("a/dup.md")
        let deep2   = createFile("c/dup.md")
        switch repo.resolveFile("dup.md") {
        case .ambiguous(let urls):
            XCTAssertEqual(urls.count, 3)
            // 深度优先：a/dup.md 与 c/dup.md 同深度（排前，按字母序），a/b/dup.md 最深排最后
            XCTAssertEqual(urls[0], shallow)
            XCTAssertEqual(urls[1], deep2)
            XCTAssertEqual(urls[2], deep)
        default: XCTFail("多个同名文件应 .ambiguous")
        }
    }

    func testResolveFile_ignoresNoiseDirectories() {
        createFile("node_modules/pkg/readme.md")
        switch repo.resolveFile("readme.md") {
        case .notFound: break   // node_modules 内的文件不参与解析
        case .ambiguous(let urls): XCTFail("noise 目录不应产生候选：\(urls)")
        case .found(let url): XCTFail("不应解析到 noise 目录内文件：\(url)")
        }
    }

    func testResolveFile_dotdotWithinWorkspace_standardizesAndFinds() {
        createDir("sub")
        let file = createFile("escape.md", content: "x")
        // "sub/../escape.md" 标准化后命中工作区内文件
        switch repo.resolveFile("sub/../escape.md") {
        case .found(let url): XCTAssertEqual(url, file.standardizedFileURL)
        default: XCTFail("../ 应被标准化后解析")
        }
    }

    func testResolveFile_dotdotMiss_fallsBackToBareNameSearch() {
        // 当前实现行为：带 ../ 的路径标准化后不存在时，退化为按文件名全工作区搜索。
        // （读路径宽松解析；写入越界由 AgentContext.validateWriteTarget 拦截。）
        let file = createFile("inside.md", content: "x")
        switch repo.resolveFile("../inside.md") {
        case .found(let url): XCTAssertEqual(url, file)
        default: XCTFail("../ 未命中时应退化为同名搜索")
        }
    }

    // MARK: - FileResolveResult.promptMessage

    func testPromptMessage_ambiguous_listsCandidates() {
        let a = createFile("x/dup.md")
        let b = createFile("y/dup.md")
        guard case .ambiguous = repo.resolveFile("dup.md"),
              let msg = repo.resolveFile("dup.md").promptMessage(forQuery: "dup.md") else {
            return XCTFail("应产生歧义提示")
        }
        XCTAssertTrue(msg.contains("2 个同名文件"), "实际：\(msg)")
        XCTAssertTrue(msg.contains("dup.md"))
        XCTAssertTrue(msg.contains(a.path) || msg.contains(b.path), "应列出候选路径，实际：\(msg)")
    }

    func testPromptMessage_nonAmbiguous_returnsNil() {
        createFile("solo.md")
        XCTAssertNil(repo.resolveFile("solo.md").promptMessage(forQuery: "solo.md"))
        XCTAssertNil(repo.resolveFile("ghost.md").promptMessage(forQuery: "ghost.md"))
    }

    // MARK: - readFile / readFileSyncFallback 解码

    func testReadFile_utf8() async throws {
        let url = createFile("hello.md", content: "# 你好\nemoji 🎉")
        let text = try await repo.readFile(at: url)
        XCTAssertEqual(text, "# 你好\nemoji 🎉")
    }

    func testReadFile_utf16WithBOM_decoded() async throws {
        let url = tempDir.appendingPathComponent("utf16.md")
        try "UTF-16 内容：中文字符".data(using: .utf16)!.write(to: url)
        let text = try await repo.readFile(at: url)
        XCTAssertEqual(text, "UTF-16 内容：中文字符")
    }

    func testReadFile_truncatedMultibyteTail_recovered() async throws {
        // 文件被截断在多字节 UTF-8 字符中间：解码器应丢弃残缺尾部而不是整体乱码/失败
        let full = "ASCII prefix 中文尾巴"
        var data = full.data(using: .utf8)!
        data.removeLast(1)   // 切掉 "巴" 的最后一个字节
        let url = tempDir.appendingPathComponent("trunc.md")
        try data.write(to: url)

        let text = try await repo.readFile(at: url)
        XCTAssertTrue(text.hasPrefix("ASCII prefix 中文尾"),
                      "截断字节应被容忍，保留可解码部分，实际：\(text)")
    }

    func testReadFile_undecodableBytes_throwsFileNotReadable() async {
        // 构造在 UTF-8（含截断重试）/ UTF-16 双端 / UTF-32 双端下均非法的字节：
        // BE 视角 0xD800 高代理未配对；LE 视角尾部 0xD800 未配对；4 字节 0xD80000D8 超 Unicode 上限
        let url = tempDir.appendingPathComponent("binary.md")
        try! Data([0xD8, 0x00, 0x00, 0xD8]).write(to: url)
        do {
            _ = try await repo.readFile(at: url)
            XCTFail("不可解码文件应抛错")
        } catch AgentContextError.fileNotReadable(let name) {
            XCTAssertEqual(name, "binary.md")
        } catch {
            XCTFail("应抛 fileNotReadable，实际：\(error)")
        }
    }

    func testReadFile_longContent_truncatedWithMarker() async throws {
        let long = String(repeating: "x", count: DefaultAgentFileRepository.maxReadBytes + 500)
        let url = createFile("long.md", content: long)
        let text = try await repo.readFile(at: url)
        XCTAssertTrue(text.contains("[truncated: showing first"), "应附截断标记，实际尾部：\(text.suffix(80))")
        XCTAssertTrue(text.hasPrefix(String(repeating: "x", count: 100)))
    }

    func testReadFile_exactlyAtLimit_notTruncated() async throws {
        let exact = String(repeating: "y", count: DefaultAgentFileRepository.maxReadBytes)
        let url = createFile("exact.md", content: exact)
        let text = try await repo.readFile(at: url)
        XCTAssertEqual(text, exact)
    }

    func testReadFileSyncFallback_matchesAsyncRead() throws {
        let url = createFile("sync.md", content: "同步读取内容")
        let text = try repo.readFileSyncFallback(at: url)
        XCTAssertEqual(text, "同步读取内容")
    }

    func testReadFile_missingFile_throws() async {
        let url = tempDir.appendingPathComponent("nope.md")
        do {
            _ = try await repo.readFile(at: url)
            XCTFail("缺失文件应抛错")
        } catch {
            // CocoaError fileReadNoSuchFile — 具体类型不做强约束，但必须抛
        }
    }

    // MARK: - readDiskFull

    func testReadDiskFull_utf8_returnsFullContent() async throws {
        let content = String(repeating: "完整读取\n", count: 10_000)
        let url = createFile("full.md", content: content)
        let text = try await repo.readDiskFull(at: url)
        XCTAssertEqual(text, content)
    }

    func testReadDiskFull_utf16File_throwsFileNotReadable() async throws {
        // readDiskFull 只认 UTF-8（与 readFile 的多编码 fallback 是刻意的行为差）
        let url = tempDir.appendingPathComponent("utf16full.md")
        try "中文内容".data(using: .utf16)!.write(to: url)
        do {
            _ = try await repo.readDiskFull(at: url)
            XCTFail("UTF-16 文件应抛 fileNotReadable")
        } catch AgentContextError.fileNotReadable(let name) {
            XCTAssertEqual(name, "utf16full.md")
        }
    }

    func testReadDiskFull_oversizedFile_throwsFileTooLarge() async throws {
        let url = tempDir.appendingPathComponent("huge.md")
        let big = Data(repeating: 0x61, count: DefaultAgentFileRepository.maxFullReadBytes + 1)
        try big.write(to: url)
        do {
            _ = try await repo.readDiskFull(at: url)
            XCTFail("超限文件应抛 fileTooLarge")
        } catch AgentContextError.fileTooLarge(let name, let size) {
            XCTAssertEqual(name, "huge.md")
            XCTAssertEqual(size, DefaultAgentFileRepository.maxFullReadBytes + 1)
        }
    }

    // MARK: - writeDisk / 高级磁盘操作

    func testWriteDisk_writesUTF8Atomically() throws {
        let url = tempDir.appendingPathComponent("out.md")
        try repo.writeDisk("写入内容 ✓", to: url)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "写入内容 ✓")
    }

    func testCreateFile_createsWithIntermediateDirs() throws {
        let url = try repo.createFile(name: "new/deep/file.md", content: "fresh")
        XCTAssertEqual(url.path, tempDir.appendingPathComponent("new/deep/file.md").path)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "fresh")
    }

    func testCreateFile_existing_throwsFileAlreadyExists() throws {
        createFile("dup.md", content: "old")
        XCTAssertThrowsError(try repo.createFile(name: "dup.md", content: "new")) { error in
            guard case AgentContextError.fileAlreadyExists(let name) = error else {
                return XCTFail("应抛 fileAlreadyExists，实际：\(error)")
            }
            XCTAssertEqual(name, "dup.md")
        }
        // 原内容未被覆盖
        XCTAssertEqual(try String(contentsOf: tempDir.appendingPathComponent("dup.md"), encoding: .utf8), "old")
    }

    func testWriteFile_overwritesExisting() throws {
        createFile("ow.md", content: "old")
        let url = try repo.writeFile(name: "ow.md", content: "new")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "new")
    }

    func testCreateDirectory_createsNested() throws {
        let url = try repo.createDirectory(name: "a/b/c")
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)
    }

    // MARK: - listWorkspaceFiles

    func testListWorkspaceFiles_filtersExtensionsAndNoise() async {
        createFile("keep.md")
        createFile("keep.txt")
        createFile("skip.js")
        createFile("node_modules/dep.md")
        let files = await repo.listWorkspaceFiles(extensions: ["md", "txt"])
        let names = files.map(\.lastPathComponent)
        XCTAssertTrue(names.contains("keep.md"))
        XCTAssertTrue(names.contains("keep.txt"))
        XCTAssertFalse(names.contains("skip.js"))
        XCTAssertFalse(names.contains("dep.md"), "node_modules 应被跳过")
    }

    func testListWorkspaceFiles_noWorkspace_returnsEmpty() async {
        let noRoot = DefaultAgentFileRepository { nil }
        let files = await noRoot.listWorkspaceFiles(extensions: [])
        XCTAssertTrue(files.isEmpty)
    }

    func testListWorkspaceFiles_extensionMatchIsCaseInsensitive() async {
        createFile("UPPER.MD")
        let files = await repo.listWorkspaceFiles(extensions: ["md"])
        XCTAssertTrue(files.map(\.lastPathComponent).contains("UPPER.MD"))
    }

    // MARK: - searchWorkspace：grep 快路径（macOS）

    func testSearchWorkspace_grepFastPath_findsCaseInsensitiveMatches() async throws {
        // 无正则元字符的 query 走 /usr/bin/grep 快路径（macOS）
        createFile("a.md", content: "Hello Agent\nsecond line")
        createFile("b.md", content: "nothing here\nAGENT again")

        let results = await repo.searchWorkspace(query: "agent", extensions: ["md"])
        XCTAssertEqual(results.count, 2, "实际：\(results)")
        XCTAssertTrue(results.contains { $0.hasPrefix("a.md:1:") && $0.contains("Hello Agent") },
                      "结果应为 相对路径:行号: 内容 格式，实际：\(results)")
        XCTAssertTrue(results.contains { $0.hasPrefix("b.md:2:") }, "应大小写不敏感，实际：\(results)")
    }

    func testSearchWorkspace_grepFastPath_respectsExtensionsAndNoise() async {
        createFile("doc.md", content: "needle")
        createFile("code.js", content: "needle")
        createFile("node_modules/dep.md", content: "needle")

        let results = await repo.searchWorkspace(query: "needle", extensions: ["md"])
        XCTAssertEqual(results.count, 1, "只搜 md 且跳过 noise 目录，实际：\(results)")
        XCTAssertTrue(results[0].hasPrefix("doc.md:"))
    }

    func testSearchWorkspace_noMatch_returnsEmpty() async {
        createFile("a.md", content: "nothing")
        let results = await repo.searchWorkspace(query: "zzzabsent", extensions: ["md"])
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - searchWorkspace：grep 快路径 `--` 分隔（`-` 开头的 query 不被当成 flag）

    func testSearchWorkspace_dashPrefixedQuery_searchesLiterally() async throws {
        // "-needle" 含正则元字符检查之外的 `-`：修复前会被 grep 当成未知 flag
        //（exit 2 静默回退慢路径）；query 恰为合法 flag（如 "-r"）时 root 路径会被
        // 当作 pattern、grep 读 stdin 挂起。现在 pattern/路径前插 `--`，走快路径直搜。
        createFile("flag.md", content: "use -needle option here\nnothing on this line")

        let results = await repo.searchWorkspace(query: "-needle", extensions: ["md"])
        XCTAssertEqual(results.count, 1, "`-` 开头的 query 应按字面搜到，实际：\(results)")
        XCTAssertTrue(results[0].hasPrefix("flag.md:1:"), "实际：\(results)")
        XCTAssertTrue(results[0].contains("-needle"))
    }

    func testSearchWorkspace_queryLooksLikeGrepFlag_notMisparsed() async throws {
        // "-i" 是合法 grep flag：修复前会被当选项吞掉，root.path 变成 pattern 导致误搜/挂起
        createFile("dash.md", content: "the -i flag is case insensitive")

        let results = await repo.searchWorkspace(query: "-i", extensions: ["md"])
        XCTAssertEqual(results.count, 1, "query 恰为合法 flag 时应按字面搜到，实际：\(results)")
        XCTAssertTrue(results[0].hasPrefix("dash.md:1:"), "实际：\(results)")
    }

    func testSearchWorkspace_noWorkspace_returnsEmpty() async {
        let noRoot = DefaultAgentFileRepository { nil }
        let results = await noRoot.searchWorkspace(query: "agent", extensions: ["md"])
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - searchWorkspace：swiftSearch 慢路径（正则元字符 query 强制回退）

    func testSearchWorkspace_swiftFallback_literalMatchNotRegex() async {
        // 含正则元字符的 query 被 grep 快路径拒绝 → swiftSearch，且按字面匹配
        createFile("literal.md", content: "price is a.b here\nprice is axb here")
        let results = await repo.searchWorkspace(query: "a.b", extensions: ["md"])
        XCTAssertEqual(results.count, 1, "字面搜索只命中 a.b，不命中 axb（正则会命中），实际：\(results)")
        XCTAssertTrue(results[0].contains("price is a.b here"))
        XCTAssertTrue(results[0].hasPrefix("literal.md:1:"))
    }

    func testSearchWorkspace_swiftFallback_caseInsensitive() async {
        createFile("case.md", content: "MixedCase (Token) here")
        let results = await repo.searchWorkspace(query: "mixedcase (token)", extensions: ["md"])
        XCTAssertEqual(results.count, 1, "实际：\(results)")
    }

    func testSearchWorkspace_swiftFallback_capsAtFiveMatchesPerFile() async {
        let lines = (1...10).map { "hit( line \($0)" }.joined(separator: "\n")
        createFile("many.md", content: lines)
        let results = await repo.searchWorkspace(query: "hit(", extensions: ["md"])
        XCTAssertEqual(results.count, 5, "单文件最多 5 条，实际：\(results)")
        XCTAssertTrue(results[0].hasPrefix("many.md:1:"))
        XCTAssertTrue(results[4].hasPrefix("many.md:5:"))
    }

    func testSearchWorkspace_swiftFallback_skipsUndecodableFileWithNote() async {
        createFile("good.md", content: "needle() here")
        let bad = tempDir.appendingPathComponent("bad.md")
        try! Data([0xD8, 0x00, 0x00, 0xD8]).write(to: bad)

        let results = await repo.searchWorkspace(query: "needle(", extensions: ["md"])
        XCTAssertTrue(results.contains { $0.hasPrefix("good.md:1:") }, "实际：\(results)")
        XCTAssertTrue(results.contains { $0.contains("无法解码") && $0.contains("bad.md") },
                      "不可解码文件应被列出为跳过，实际：\(results)")
    }

    func testSearchWorkspace_swiftFallback_matchesAnywhereInLine() async {
        createFile("mid.md", content: "prefix target[] suffix")
        let results = await repo.searchWorkspace(query: "target[]", extensions: ["md"])
        XCTAssertEqual(results.count, 1, "实际：\(results)")
    }

    // MARK: - PatchNotFoundError（patch 失败时给 AI 的报错格式）

    func testPatchNotFoundError_descriptionContainsFindContextAndAdvice() {
        let err = PatchNotFoundError(find: "missing anchor text", nearbyContext: "L1: some line")
        let desc = err.errorDescription ?? ""
        XCTAssertTrue(desc.contains("missing anchor text"), "应包含 find 文本，实际：\(desc)")
        XCTAssertTrue(desc.contains("L1: some line"), "应包含附近上下文，实际：\(desc)")
        XCTAssertTrue(desc.contains("read_document"), "应包含重读建议，实际：\(desc)")
    }

    func testPatchNotFoundError_longFind_truncatedToSixtyChars() {
        let longFind = String(repeating: "f", count: 100)
        let err = PatchNotFoundError(find: longFind, nearbyContext: "ctx")
        let desc = err.errorDescription ?? ""
        XCTAssertFalse(desc.contains(String(repeating: "f", count: 100)),
                       "find 应被截断到 60 字符，实际：\(desc)")
        XCTAssertTrue(desc.contains(String(repeating: "f", count: 60)))
    }
}
