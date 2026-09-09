import XCTest
@testable import MEditor

// MARK: - AgentSkillStoreTests
//
// Agent Skills（用户自定义技能文件，渐进披露）的单测：
//   发现/解析（frontmatter 有无、缺字段、坏文件容错、目录与平铺两种布局、同名覆盖）、
//   目录注入（只注入 name+description，不含正文；空目录零变化）、
//   load_skill 工具（正文 + 附属文件清单、未知名字、路径穿越清洗）。
// fixture 全部用临时目录，不依赖真实 ~/.meditor。
//
// 文案断言只针对硬编码字面量（不走 L() 本地化），CI 英文 locale 下稳定。

@MainActor
final class AgentSkillStoreTests: XCTestCase {

    private var tempRoot: URL!
    private var globalDir: URL!
    private var workspaceRoot: URL!
    private var wsSkillsDir: URL!
    private var savedStore: AgentSkillStore!
    private var ctx: MockAgentContext!
    private var cfg: AIConfig!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("meditor-skills-\(UUID().uuidString)", isDirectory: true)
        globalDir     = tempRoot.appendingPathComponent("global", isDirectory: true)
        workspaceRoot = tempRoot.appendingPathComponent("ws", isDirectory: true)
        wsSkillsDir   = workspaceRoot.appendingPathComponent(".meditor/skills", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: globalDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: wsSkillsDir, withIntermediateDirectories: true)
        savedStore = AgentSkillStore.shared   // Runner 注入测试会替换 shared，用后还原
        ctx = MockAgentContext()
        ctx.workspaceURL = workspaceRoot
        cfg = AIConfig(kind: .disabled, baseURL: "", model: "", cliPath: "", cliModel: "",
                       apiKey: "", requestTimeoutSeconds: 60)
    }

    override func tearDownWithError() throws {
        AgentSkillStore.shared = savedStore
        try? FileManager.default.removeItem(at: tempRoot)
        savedStore = nil; ctx = nil; cfg = nil
        wsSkillsDir = nil; workspaceRoot = nil; globalDir = nil; tempRoot = nil
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    /// 测试用 store：全局目录指向临时目录，内置技能默认空（注入式，保证确定性）。
    private func makeStore(builtins: [AgentSkill] = []) -> AgentSkillStore {
        AgentSkillStore(globalDirectory: globalDir) { builtins }
    }

    private func write(_ content: String, _ relPath: String, in root: URL) throws {
        let url = root.appendingPathComponent(relPath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    private func builtinSkill(_ name: String) -> AgentSkill {
        AgentSkill(name: name, description: "builtin \(name)",
                   source: .builtin, content: "BUILTIN_BODY_\(name)")
    }

    // MARK: - 解析：目录型 + 完整 frontmatter

    func test_directoryLayout_parsesFrontmatter() throws {
        try write("""
        ---
        name: pdf-tools
        description: PDF processing skill
        version: 1.2
        ---

        You are a PDF expert. BODY_MARKER_PDF
        """, "pdf-tools/SKILL.md", in: globalDir)

        let store = makeStore()
        store.refresh(workspaceURL: nil)

        let skill = try XCTUnwrap(store.skill(named: "pdf-tools"))
        XCTAssertEqual(skill.name, "pdf-tools")
        XCTAssertEqual(skill.description, "PDF processing skill")
        XCTAssertEqual(skill.version, "1.2")
        XCTAssertEqual(skill.source, .global)
        XCTAssertNotNil(skill.directoryURL, "目录型技能应记录技能目录")
        XCTAssertTrue(skill.content.contains("BODY_MARKER_PDF"))
        XCTAssertTrue(store.loadErrors.isEmpty)
    }

    // MARK: - 解析：平铺 .md + 无 frontmatter 回退

    func test_flatLayout_noFrontmatter_fallbackNameAndDescription() throws {
        try write("First line description here.\n\nMore body.", "notes.md", in: globalDir)

        let store = makeStore()
        store.refresh(workspaceURL: nil)

        let skill = try XCTUnwrap(store.skill(named: "notes"))
        XCTAssertEqual(skill.description, "First line description here.")
        XCTAssertNil(skill.version)
        XCTAssertNil(skill.directoryURL, "平铺 .md 没有技能目录")
        XCTAssertTrue(skill.attachments.isEmpty)
    }

    func test_noFrontmatter_headingFirstLine_strippedAsDescription() throws {
        try write("# My Title\n\nbody text", "titled.md", in: globalDir)
        let store = makeStore()
        store.refresh(workspaceURL: nil)
        XCTAssertEqual(store.skill(named: "titled")?.description, "My Title")
    }

    // MARK: - 解析：frontmatter 缺字段回退

    func test_frontmatterMissingName_usesFileName() throws {
        try write("""
        ---
        description: only description
        ---

        body
        """, "fallback-name/SKILL.md", in: globalDir)

        let store = makeStore()
        store.refresh(workspaceURL: nil)

        let skill = try XCTUnwrap(store.skill(named: "fallback-name"))
        XCTAssertEqual(skill.description, "only description")
    }

    func test_frontmatterMissingDescription_usesFirstBodyLine() throws {
        try write("""
        ---
        name: partial
        ---

        Body first line as description.
        """, "partial/SKILL.md", in: globalDir)

        let store = makeStore()
        store.refresh(workspaceURL: nil)

        XCTAssertEqual(store.skill(named: "partial")?.description, "Body first line as description.")
    }

    // MARK: - 解析：坏文件容错（跳过并记录，不拖垮加载）

    func test_unterminatedFrontmatter_treatedAsNoFrontmatter() throws {
        try write("---\nname: ghost\nno closing fence\nreal body line", "ghost.md", in: globalDir)

        let store = makeStore()
        store.refresh(workspaceURL: nil)

        // 未闭合的 --- 不构成 frontmatter：name 回退为文件名，仍能加载
        let skill = try XCTUnwrap(store.skill(named: "ghost"))
        XCTAssertFalse(skill.description.isEmpty)
    }

    func test_invalidUTF8File_skippedAndRecorded() throws {
        let dir = globalDir.appendingPathComponent("broken", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // 截断的多字节序列：非法 UTF-8
        try Data([0xE3, 0x81]).write(to: dir.appendingPathComponent("SKILL.md"))
        try write("good body", "good.md", in: globalDir)

        let store = makeStore()
        store.refresh(workspaceURL: nil)

        XCTAssertNil(store.skill(named: "broken"), "坏文件应被跳过")
        XCTAssertNotNil(store.skill(named: "good"), "坏文件不得拖垮其余技能的加载")
        XCTAssertEqual(store.loadErrors.count, 1, "坏文件应记入 loadErrors")
    }

    func test_emptyFile_skippedAndRecorded() throws {
        try write("   \n  \n", "empty.md", in: globalDir)
        let store = makeStore()
        store.refresh(workspaceURL: nil)
        XCTAssertTrue(store.skills.isEmpty)
        XCTAssertEqual(store.loadErrors.count, 1)
    }

    func test_unsafeFrontmatterName_skippedAndRecorded() throws {
        try write("""
        ---
        name: ../escape
        ---

        body
        """, "evil/SKILL.md", in: globalDir)

        let store = makeStore()
        store.refresh(workspaceURL: nil)

        XCTAssertTrue(store.skills.isEmpty, "含路径穿越片段的技能名应被拒绝")
        XCTAssertEqual(store.loadErrors.count, 1)
    }

    func test_directoryWithoutSkillMD_ignoredSilently() throws {
        try write("not a skill", "random/readme.txt", in: globalDir)
        let store = makeStore()
        store.refresh(workspaceURL: nil)
        XCTAssertTrue(store.skills.isEmpty)
        XCTAssertTrue(store.loadErrors.isEmpty, "无 SKILL.md 的目录不算坏文件，静默跳过")
    }

    // MARK: - 同名覆盖

    func test_workspaceOverridesGlobal_sameName() throws {
        try write("---\nname: duo\ndescription: global version\n---\n\nglobal body",
                  "duo/SKILL.md", in: globalDir)
        try write("---\nname: duo\ndescription: workspace version\n---\n\nws body",
                  "duo/SKILL.md", in: wsSkillsDir)

        let store = makeStore()
        store.refresh(workspaceURL: workspaceRoot)

        let matches = store.skills.filter { $0.name == "duo" }
        XCTAssertEqual(matches.count, 1, "同名技能只保留一个")
        XCTAssertEqual(matches.first?.source, .workspace, "工作区级覆盖全局")
        XCTAssertEqual(matches.first?.description, "workspace version")
    }

    func test_userSkillOverridesBuiltin_markedInCatalog() throws {
        try write("---\nname: 美化\ndescription: user override\n---\n\nuser body",
                  "美化/SKILL.md", in: globalDir)

        let store = makeStore(builtins: [builtinSkill("美化"), builtinSkill("内联编辑")])
        store.refresh(workspaceURL: nil)

        let overridden = store.skills.filter { $0.name == "美化" }
        XCTAssertEqual(overridden.count, 1, "同名内置被用户技能遮蔽")
        XCTAssertEqual(overridden.first?.source, .global)
        XCTAssertTrue(overridden.first?.overridesBuiltin == true, "目录里应标注覆盖内置")
        XCTAssertNotNil(store.skill(named: "内联编辑"), "未被覆盖的内置照常列出")

        let section = try XCTUnwrap(store.catalogPromptSection())
        XCTAssertTrue(section.contains("overrides built-in"))
    }

    // MARK: - 目录注入（渐进披露）

    func test_catalogSection_listsNamesDescriptionsSources_notBody() throws {
        try write("---\nname: pdf-tools\ndescription: PDF work\n---\n\nBODY_SECRET_PDF",
                  "pdf-tools/SKILL.md", in: globalDir)
        try write("---\nname: ws-skill\ndescription: workspace work\n---\n\nBODY_SECRET_WS",
                  "ws-skill/SKILL.md", in: wsSkillsDir)

        let store = makeStore(builtins: [builtinSkill("美化")])
        store.refresh(workspaceURL: workspaceRoot)

        let section = try XCTUnwrap(store.catalogPromptSection())
        XCTAssertTrue(section.contains("`pdf-tools`"), "目录应含技能名")
        XCTAssertTrue(section.contains("PDF work"), "目录应含描述")
        XCTAssertTrue(section.contains("[workspace]"), "目录应标注工作区来源")
        XCTAssertTrue(section.contains("[user]"), "目录应标注全局（用户级）来源")
        XCTAssertTrue(section.contains("[built-in]"), "目录应标注内置来源")
        XCTAssertTrue(section.contains("load_skill"), "目录应指引模型使用 load_skill")
        XCTAssertFalse(section.contains("BODY_SECRET_PDF"), "目录不得含技能正文")
        XCTAssertFalse(section.contains("BODY_SECRET_WS"), "目录不得含技能正文")
        XCTAssertFalse(section.contains("BUILTIN_BODY"), "目录不得含内置技能正文")
    }

    func test_catalogSection_emptyWhenNoSkills() {
        let store = makeStore()
        store.refresh(workspaceURL: workspaceRoot)
        XCTAssertNil(store.catalogPromptSection(), "无技能时目录段为 nil（系统提示零改动）")
    }

    // MARK: - 附属文件清单

    func test_attachments_listedRecursively_notLoaded() throws {
        try write("---\nname: rich\n---\n\nbody", "rich/SKILL.md", in: wsSkillsDir)
        try write("echo hi", "rich/scripts/run.sh", in: wsSkillsDir)
        try write("tpl ATTACHMENT_CONTENT_MARKER", "rich/templates/t.md", in: wsSkillsDir)

        let store = makeStore()
        store.refresh(workspaceURL: workspaceRoot)

        let skill = try XCTUnwrap(store.skill(named: "rich"))
        XCTAssertEqual(skill.attachments, ["scripts/run.sh", "templates/t.md"],
                       "附属文件为相对路径清单（递归、不含 SKILL.md 本身）")
        XCTAssertFalse(skill.content.contains("ATTACHMENT_CONTENT_MARKER"),
                       "附属文件只列路径、不读内容")
    }

    // MARK: - 缓存与刷新

    func test_refreshIfNeeded_rescansWhenWorkspaceChanges() throws {
        try write("---\nname: ws-one\n---\n\none", "ws-one/SKILL.md", in: wsSkillsDir)
        let otherRoot = tempRoot.appendingPathComponent("ws2", isDirectory: true)
        try write("---\nname: ws-two\n---\n\ntwo", ".meditor/skills/ws-two/SKILL.md", in: otherRoot)

        let store = makeStore()
        store.refresh(workspaceURL: workspaceRoot)
        XCTAssertNotNil(store.skill(named: "ws-one"))

        store.refreshIfNeeded(workspaceURL: workspaceRoot)
        XCTAssertNotNil(store.skill(named: "ws-one"), "同工作区不重复扫描，缓存仍可用")

        store.refreshIfNeeded(workspaceURL: otherRoot)
        XCTAssertNil(store.skill(named: "ws-one"), "工作区切换后按新工作区重扫")
        XCTAssertNotNil(store.skill(named: "ws-two"))
    }

    // MARK: - load_skill 工具

    func test_loadSkill_returnsBodyAndAttachmentList() async throws {
        try write("---\nname: pdf-tools\n---\n\nFULL_BODY_PDF", "pdf-tools/SKILL.md", in: wsSkillsDir)
        try write("echo hi", "pdf-tools/scripts/run.sh", in: wsSkillsDir)

        let tool = LoadSkillTool(store: makeStore())
        let result = try await tool.execute(
            arguments: ["name": .string("pdf-tools")], context: ctx)

        XCTAssertTrue(result.contains("FULL_BODY_PDF"), "应返回技能全文")
        XCTAssertTrue(result.contains("SKILL_DIR"), "应给出技能目录绝对路径")
        XCTAssertTrue(result.contains("scripts/run.sh"), "应列出附属文件相对路径")
        XCTAssertFalse(result.contains("echo hi"), "附属文件只列路径、不读内容")
    }

    func test_loadSkill_flatSkill_noSkillDirNoAttachments() async throws {
        try write("flat body marker", "flat.md", in: wsSkillsDir)

        let tool = LoadSkillTool(store: makeStore())
        let result = try await tool.execute(arguments: ["name": .string("flat")], context: ctx)

        XCTAssertTrue(result.contains("flat body marker"))
        XCTAssertFalse(result.contains("SKILL_DIR"), "平铺技能没有技能目录")
    }

    func test_loadSkill_builtinByName() async throws {
        let tool = LoadSkillTool(store: makeStore(builtins: [builtinSkill("美化")]))
        let result = try await tool.execute(arguments: ["name": .string("美化")], context: ctx)
        XCTAssertTrue(result.contains("BUILTIN_BODY_美化"))
    }

    func test_loadSkill_unknownName_listsAvailable() async throws {
        try write("---\nname: pdf-tools\n---\n\nbody", "pdf-tools/SKILL.md", in: wsSkillsDir)

        let tool = LoadSkillTool(store: makeStore())
        let result = try await tool.execute(
            arguments: ["name": .string("nonexistent")], context: ctx)

        XCTAssertTrue(result.contains("[!]"), "未知名字应返回给模型的错误文案，实际：\(result)")
        XCTAssertTrue(result.contains("pdf-tools"), "错误文案应列出可用技能名帮助模型纠正")
    }

    func test_loadSkill_pathTraversalName_rejected() async throws {
        try write("---\nname: legit\n---\n\nLEGIT_BODY", "legit/SKILL.md", in: wsSkillsDir)
        // 在工作区外放一个敏感文件，验证穿越名不会读到它
        try write("TOP_SECRET", "outside.md", in: tempRoot)

        let tool = LoadSkillTool(store: makeStore())
        for bad in ["../outside", "../../outside", "legit/../../outside", "a/b", "a\\b"] {
            let result = try await tool.execute(arguments: ["name": .string(bad)], context: ctx)
            XCTAssertTrue(result.contains("[!]"), "穿越/非法名字应被拒绝：\(bad)")
            XCTAssertFalse(result.contains("TOP_SECRET"), "不得泄露技能目录外内容：\(bad)")
        }
    }

    func test_loadSkill_missingName_throws() async {
        let tool = LoadSkillTool(store: makeStore())
        do {
            _ = try await tool.execute(arguments: [:], context: ctx)
            XCTFail("缺少 name 参数应抛错")
        } catch {
            // 预期路径：参数缺失抛 AgentError.executionError
        }
    }

    func test_loadSkillTool_registeredInBuiltinTools() {
        XCTAssertNotNil(BuiltinAgentTools.tool(named: "load_skill"), "load_skill 应注册进内建工具表")
    }

    // MARK: - AgentRunner 注入

    func test_runner_injectsCatalogIntoSystemMessage_notBody() async throws {
        try write("---\nname: pdf-tools\ndescription: PDF work\n---\n\nRUNNER_BODY_SECRET",
                  "pdf-tools/SKILL.md", in: globalDir)
        let store = makeStore()   // 无内置，保证断言确定
        AgentSkillStore.shared = store

        let backend = CapturingBackend()
        let runner = AgentRunner(maxSteps: 3, backendFactory: { _ in backend })
        await runAndWait(runner, tools: [LoadSkillTool(store: store)], messages: [
            AgentMessage(role: .system, content: "SYS_PROMPT"),
            AgentMessage(role: .user, content: "hi"),
        ])

        let sent = try XCTUnwrap(backend.captured.first)
        let system = try XCTUnwrap(sent.first { $0.role == .system })
        XCTAssertTrue(system.content.contains("SYS_PROMPT"), "原系统提示应保留")
        XCTAssertTrue(system.content.contains("## Available Skills"), "应注入技能目录段")
        XCTAssertTrue(system.content.contains("`pdf-tools`"), "目录应含技能名")
        XCTAssertTrue(system.content.contains("PDF work"), "目录应含描述")
        XCTAssertFalse(system.content.contains("RUNNER_BODY_SECRET"), "目录不得含技能正文")
    }

    func test_runner_noSkills_systemPromptUntouched() async throws {
        let store = makeStore()   // 空目录 + 无内置
        AgentSkillStore.shared = store

        let backend = CapturingBackend()
        let runner = AgentRunner(maxSteps: 3, backendFactory: { _ in backend })
        await runAndWait(runner, tools: [LoadSkillTool(store: store)], messages: [
            AgentMessage(role: .system, content: "SYS_PROMPT"),
            AgentMessage(role: .user, content: "hi"),
        ])

        let sent = try XCTUnwrap(backend.captured.first)
        let system = try XCTUnwrap(sent.first { $0.role == .system })
        XCTAssertEqual(system.content, "SYS_PROMPT", "无技能时系统提示必须零变化")
    }

    func test_runner_withoutLoadSkillTool_noInjection() async throws {
        // slash 命令等按 allowedTools 过滤工具的路径没有 load_skill：
        // 注入目录会让模型去调不存在的工具，此时必须不注入
        try write("---\nname: pdf-tools\ndescription: PDF work\n---\n\nbody",
                  "pdf-tools/SKILL.md", in: globalDir)
        AgentSkillStore.shared = makeStore()

        let backend = CapturingBackend()
        let runner = AgentRunner(maxSteps: 3, backendFactory: { _ in backend })
        await runAndWait(runner, tools: [], messages: [
            AgentMessage(role: .system, content: "SYS_PROMPT"),
            AgentMessage(role: .user, content: "hi"),
        ])

        let sent = try XCTUnwrap(backend.captured.first)
        let system = try XCTUnwrap(sent.first { $0.role == .system })
        XCTAssertEqual(system.content, "SYS_PROMPT", "未注册 load_skill 时不得注入技能目录")
    }

    func test_runner_noSystemMessage_skipsInjection() async throws {
        try write("---\nname: pdf-tools\n---\n\nbody", "pdf-tools/SKILL.md", in: globalDir)
        let store = makeStore()
        AgentSkillStore.shared = store

        let backend = CapturingBackend()
        let runner = AgentRunner(maxSteps: 3, backendFactory: { _ in backend })
        await runAndWait(runner, tools: [LoadSkillTool(store: store)],
                         messages: [AgentMessage(role: .user, content: "hi")])

        let sent = try XCTUnwrap(backend.captured.first)
        XCTAssertFalse(sent.contains { $0.role == .system },
                       "没有 system 消息时不插入新消息（保持既有 wire 结构）")
        XCTAssertEqual(runner.finalText, "done")
    }

    private func runAndWait(
        _ runner: AgentRunner,
        tools: [any AgentTool],
        messages: [AgentMessage]
    ) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            runner.onComplete = { cont.resume() }
            runner.run(messages: messages, tools: tools, config: cfg, context: ctx)
        }
    }
}

// MARK: - CapturingBackend

/// 记录每次 complete 收到的消息列表、首轮即返回最终文本的 backend（不进工具循环）。
private final class CapturingBackend: AgentBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var _captured: [[AgentMessage]] = []
    var captured: [[AgentMessage]] { lock.lock(); defer { lock.unlock() }; return _captured }

    func complete(messages: [AgentMessage], tools: [any AgentTool]) async throws -> AgentCompletionResponse {
        lock.lock(); _captured.append(messages); lock.unlock()
        return AgentCompletionResponse(text: "done", toolCalls: [], finishReason: "stop")
    }
}
