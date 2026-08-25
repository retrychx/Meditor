import XCTest
@testable import MEditor

/// 技能导入/导出（分享）测试：解析校验、URL 安全边界、导出往返、安装冲突处理。
/// CI 是英文 locale，断言只针对错误类型/结构，不写死任一语言的文案。
@MainActor
final class SkillTransferTests: XCTestCase {

    private func cleanDefaults() {
        UserDefaults.standard.removeObject(forKey: "MEditor.pluginManualSkills")
        UserDefaults.standard.removeObject(forKey: "MEditor.pluginSkillStates")
    }

    override func setUp() { super.setUp(); cleanDefaults() }
    override func tearDown() { cleanDefaults(); super.tearDown() }

    private func makeTempDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("meditor-skill-transfer-\(UUID().uuidString)", isDirectory: true)
    }

    private let validDoc = """
    ---
    name: Shared Skill
    description: A skill shared between users
    ---

    You are a helpful assistant.

    ## Rules
    - Be concise
    """

    // MARK: - 解析与校验

    func test_parse_validDocument_extractsFields() throws {
        let parsed = try SkillTransfer.parse(validDoc)
        XCTAssertEqual(parsed.name, "Shared Skill")
        XCTAssertEqual(parsed.description, "A skill shared between users")
        XCTAssertTrue(parsed.body.hasPrefix("You are a helpful assistant."))
        XCTAssertTrue(parsed.body.contains("## Rules"))
    }

    func test_parse_missingFrontmatter_throws() {
        XCTAssertThrowsError(try SkillTransfer.parse("# Just markdown\n\nNo frontmatter.")) { error in
            XCTAssertEqual(error as? SkillTransferError, .missingFrontmatter)
        }
    }

    func test_parse_missingName_throws() {
        let doc = "---\ndescription: no name here\n---\n\nBody."
        XCTAssertThrowsError(try SkillTransfer.parse(doc)) { error in
            XCTAssertEqual(error as? SkillTransferError, .missingName)
        }
    }

    func test_parse_emptyNameValue_throws() {
        let doc = "---\nname: \"\"\n---\n\nBody."
        XCTAssertThrowsError(try SkillTransfer.parse(doc)) { error in
            XCTAssertEqual(error as? SkillTransferError, .missingName)
        }
    }

    func test_parse_unsafeNames_throw() {
        for name in ["../evil", "a/b", "a\\b", ".hidden", "..", "a:b"] {
            let doc = "---\nname: \(name)\n---\n\nBody."
            XCTAssertThrowsError(try SkillTransfer.parse(doc), "name \(name) 应被拒绝") { error in
                guard case .unsafeName = (error as? SkillTransferError) else {
                    return XCTFail("name \(name) 应抛 unsafeName，实际 \(error)")
                }
            }
        }
    }

    func test_parse_emptyBody_throws() {
        let doc = "---\nname: ok\n---\n\n   \n"
        XCTAssertThrowsError(try SkillTransfer.parse(doc)) { error in
            XCTAssertEqual(error as? SkillTransferError, .emptyBody)
        }
    }

    func test_parseData_tooLarge_throws() {
        var doc = "---\nname: big\n---\n\n"
        doc += String(repeating: "x", count: SkillTransfer.maxBytes)
        let data = Data(doc.utf8)
        XCTAssertGreaterThan(data.count, SkillTransfer.maxBytes)
        XCTAssertThrowsError(try SkillTransfer.parse(data: data)) { error in
            XCTAssertEqual(error as? SkillTransferError, .tooLarge(limitKB: SkillTransfer.maxBytes / 1024))
        }
    }

    func test_parseData_notUTF8_throws() {
        // 0xFF 0xFE 开头的非法 UTF-8 序列
        let data = Data([0xFF, 0xFE, 0x00, 0x01])
        XCTAssertThrowsError(try SkillTransfer.parse(data: data)) { error in
            XCTAssertEqual(error as? SkillTransferError, .notUTF8)
        }
    }

    func test_parseData_empty_throws() {
        XCTAssertThrowsError(try SkillTransfer.parse(data: Data())) { error in
            XCTAssertEqual(error as? SkillTransferError, .emptyDocument)
        }
    }

    // MARK: - 名称工具

    func test_uniqueName_noConflict_returnsOriginal() {
        XCTAssertEqual(SkillTransfer.uniqueName(for: "foo", taken: ["bar"]), "foo")
    }

    func test_uniqueName_conflict_appendsSuffix() {
        XCTAssertEqual(SkillTransfer.uniqueName(for: "foo", taken: ["foo"]), "foo-2")
        XCTAssertEqual(SkillTransfer.uniqueName(for: "foo", taken: ["foo", "foo-2"]), "foo-3")
    }

    func test_uniqueName_caseInsensitiveConflict_appendsSuffix() {
        // APFS 默认大小写不敏感："Foo" 与已有 "foo" 落同一目录，必须加后缀防静默覆盖
        XCTAssertEqual(SkillTransfer.uniqueName(for: "Foo", taken: ["foo"]), "Foo-2")
        XCTAssertEqual(SkillTransfer.uniqueName(for: "FOO", taken: ["foo", "foo-2"]), "FOO-3")
    }

    // MARK: - URL 安全校验

    func test_validateURL_https_passes() throws {
        let url = try SkillTransfer.validateURL(" https://example.com/SKILL.md ")
        XCTAssertEqual(url.host, "example.com")
    }

    func test_validateURL_http_rejected() {
        XCTAssertThrowsError(try SkillTransfer.validateURL("http://example.com/skill.md")) { error in
            XCTAssertEqual(error as? SkillTransferError, .httpsOnly)
        }
    }

    func test_validateURL_garbage_rejected() {
        for raw in ["", "not a url", "ftp://example.com/x.md", "https://"] {
            XCTAssertThrowsError(try SkillTransfer.validateURL(raw), "\(raw) 应被拒绝")
        }
    }

    // MARK: - URL 下载（注入 mock session）

    private func makeMock(data: Data, status: Int = 200, contentType: String? = "text/markdown") -> MockURLSession {
        let mock = MockURLSession()
        mock.stubbedData = data
        var headers: [String: String] = [:]
        if let contentType { headers["Content-Type"] = contentType }
        mock.stubbedResponse = HTTPURLResponse(
            url: URL(string: "https://example.com/SKILL.md")!,
            statusCode: status,
            httpVersion: nil,
            headerFields: headers
        )!
        return mock
    }

    func test_fetchDocument_validMarkdown_succeeds() async throws {
        let mock = makeMock(data: Data(validDoc.utf8))
        let doc = try await SkillTransfer.fetchDocument(
            urlString: "https://example.com/SKILL.md", session: mock)
        XCTAssertEqual(doc, validDoc)
        XCTAssertEqual(mock.capturedRequests.first?.timeoutInterval, SkillTransfer.requestTimeout)
    }

    func test_fetchDocument_htmlContentType_rejected() async {
        let mock = makeMock(data: Data(validDoc.utf8), contentType: "text/html; charset=utf-8")
        do {
            _ = try await SkillTransfer.fetchDocument(urlString: "https://example.com/x", session: mock)
            XCTFail("text/html 应被拒绝")
        } catch let error as SkillTransferError {
            guard case .badContentType = error else {
                return XCTFail("应抛 badContentType，实际 \(error)")
            }
        } catch {
            XCTFail("应抛 SkillTransferError，实际 \(error)")
        }
    }

    func test_fetchDocument_httpError_rejected() async {
        let mock = makeMock(data: Data("not found".utf8), status: 404, contentType: nil)
        do {
            _ = try await SkillTransfer.fetchDocument(urlString: "https://example.com/x", session: mock)
            XCTFail("404 应被拒绝")
        } catch let error as SkillTransferError {
            guard case .downloadFailed = error else {
                return XCTFail("应抛 downloadFailed，实际 \(error)")
            }
        } catch {
            XCTFail("应抛 SkillTransferError，实际 \(error)")
        }
    }

    func test_fetchDocument_networkError_wrapped() async {
        let mock = makeMock(data: Data())
        mock.stubbedError = URLError(.notConnectedToInternet)
        do {
            _ = try await SkillTransfer.fetchDocument(urlString: "https://example.com/x", session: mock)
            XCTFail("网络错误应被包装")
        } catch let error as SkillTransferError {
            guard case .downloadFailed = error else {
                return XCTFail("应抛 downloadFailed，实际 \(error)")
            }
        } catch {
            XCTFail("应抛 SkillTransferError，实际 \(error)")
        }
    }

    func test_fetchDocument_tooLarge_rejected() async {
        var big = "---\nname: big\n---\n\n"
        big += String(repeating: "x", count: SkillTransfer.maxBytes)
        let mock = makeMock(data: Data(big.utf8))
        do {
            _ = try await SkillTransfer.fetchDocument(urlString: "https://example.com/x", session: mock)
            XCTFail("超限应被拒绝")
        } catch let error as SkillTransferError {
            XCTAssertEqual(error, .tooLarge(limitKB: SkillTransfer.maxBytes / 1024))
        } catch {
            XCTFail("应抛 SkillTransferError，实际 \(error)")
        }
    }

    // MARK: - 导出

    func test_normalizedDocument_roundTrip() throws {
        let doc = SkillTransfer.normalizedDocument(
            name: "My Skill", description: "Does: things", body: "Prompt body\n\nMore lines.")
        let parsed = try SkillTransfer.parse(doc)
        XCTAssertEqual(parsed.name, "My Skill")
        XCTAssertEqual(parsed.description, "Does: things")
        XCTAssertEqual(parsed.body, "Prompt body\n\nMore lines.")
    }

    func test_exportDocument_builtin_normalizesFrontmatter() async throws {
        let pm = PluginManager()
        await pm.reloadAll()
        let builtin = try XCTUnwrap(pm.skills.first { $0.source == .builtin })
        let doc = try XCTUnwrap(SkillTransfer.exportDocument(for: builtin))
        let parsed = try SkillTransfer.parse(doc)
        let def = try XCTUnwrap(BuiltinSkills.all.first { $0.id == builtin.id })
        XCTAssertEqual(parsed.name, def.name)
        XCTAssertEqual(parsed.description, def.description)
        XCTAssertEqual(parsed.body, def.content.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - 安装（导入落盘 + 冲突处理）

    func test_install_writesToDirectory_andRegisters() async throws {
        let dir = makeTempDir()
        let pm = PluginManager()
        let outcome = try SkillTransfer.install(document: validDoc, into: dir, pluginManager: pm)
        XCTAssertEqual(outcome.name, "Shared Skill")
        XCTAssertFalse(outcome.renamed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outcome.url.path))

        await pm.reloadAll()
        let skill = pm.skills.first { $0.source == .manual }
        XCTAssertEqual(skill?.name, "Shared Skill")
    }

    func test_install_conflictWithBuiltinID_autoRenames() async throws {
        let dir = makeTempDir()
        let pm = PluginManager()
        let builtinID = BuiltinSkills.ID.htmlBeautifier
        let doc = "---\nname: \(builtinID)\n---\n\nBody."
        let outcome = try SkillTransfer.install(document: doc, into: dir, pluginManager: pm)
        XCTAssertTrue(outcome.renamed)
        XCTAssertEqual(outcome.name, "\(builtinID)-2")
    }

    func test_install_sameNameTwice_secondGetsSuffix() async throws {
        let dir = makeTempDir()
        let pm = PluginManager()
        let first = try SkillTransfer.install(document: validDoc, into: dir, pluginManager: pm)
        await pm.reloadAll()
        let second = try SkillTransfer.install(document: validDoc, into: dir, pluginManager: pm)
        XCTAssertFalse(first.renamed)
        XCTAssertTrue(second.renamed)
        XCTAssertEqual(second.name, "Shared Skill-2")
    }

    // MARK: - 导出 → 导入往返

    func test_exportImport_roundTrip_equivalent() async throws {
        let dir = makeTempDir()
        let pm = PluginManager()

        // 安装一个技能 → 导出 → 再导入，内容应等价
        let first = try SkillTransfer.install(document: validDoc, into: dir, pluginManager: pm)
        await pm.reloadAll()
        let installed = try XCTUnwrap(pm.skills.first { $0.source == .manual && $0.name == first.name })
        let exported = try XCTUnwrap(SkillTransfer.exportDocument(for: installed))

        let reparsed = try SkillTransfer.parse(exported)
        XCTAssertEqual(reparsed.name, "Shared Skill")
        XCTAssertEqual(reparsed.description, "A skill shared between users")
        XCTAssertEqual(reparsed.body, try SkillTransfer.parse(validDoc).body)

        let second = try SkillTransfer.install(document: exported, into: dir, pluginManager: pm)
        await pm.reloadAll()
        XCTAssertEqual(second.name, "Shared Skill-2")
        let reimported = pm.skills.first { $0.source == .manual && $0.name == second.name }
        XCTAssertEqual(reimported?.description, "A skill shared between users")
    }
}
