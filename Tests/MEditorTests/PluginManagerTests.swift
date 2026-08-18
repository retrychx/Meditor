import XCTest
@testable import MEditor

@MainActor
final class PluginManagerTests: XCTestCase {

    private func cleanDefaults() {
        UserDefaults.standard.removeObject(forKey: "MEditor.pluginManualSkills")
        UserDefaults.standard.removeObject(forKey: "MEditor.pluginSkillStates")
    }

    override func setUp() { super.setUp(); cleanDefaults() }
    override func tearDown() { cleanDefaults(); super.tearDown() }

    private func makeSkillDir(named name: String) throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("meditor-skill-tests-\(UUID().uuidString)", isDirectory: true)
        let dir = base.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let md = """
        ---
        name: \(name)
        description: 测试技能描述
        ---

        # \(name)

        正文内容。
        """
        try md.write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        return dir
    }

    func test_addManual_folder_loadsSkill() async throws {
        let pm = PluginManager()
        let dir = try makeSkillDir(named: "my-skill")

        let ok = pm.addManual(skillMDURL: dir)
        XCTAssertTrue(ok, "选择含 SKILL.md 的文件夹应添加成功")

        await pm.reloadAll()

        let manuals = pm.skills.filter { $0.source == .manual }
        XCTAssertEqual(manuals.count, 1, "应加载到 1 个手动技能")
        XCTAssertEqual(manuals.first?.name, "my-skill")
        XCTAssertEqual(manuals.first?.description, "测试技能描述")
        XCTAssertTrue(manuals.first?.isEnabled ?? false)
    }

    func test_addManual_skillMDFile_loadsSkill() async throws {
        let pm = PluginManager()
        let dir = try makeSkillDir(named: "file-skill")
        let md  = dir.appendingPathComponent("SKILL.md")

        let ok = pm.addManual(skillMDURL: md)
        XCTAssertTrue(ok)

        await pm.reloadAll()
        XCTAssertEqual(pm.skills.filter { $0.source == .manual }.count, 1)
    }

    func test_addManual_folderWithoutSkillMD_fails() async throws {
        let pm = PluginManager()
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("meditor-noskill-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        let ok = pm.addManual(skillMDURL: base)
        XCTAssertFalse(ok, "目录中没有 SKILL.md 应返回 false")
    }

    // MARK: - BuiltinSkillDef & Commands

    func test_builtins_allHaveUniqueIDs() {
        let ids = BuiltinSkills.all.map(\.id)
        let unique = Set(ids)
        XCTAssertEqual(ids.count, unique.count, "所有内置 skill 的 ID 必须唯一")
    }

    func test_builtins_allHaveNonEmptyContent() {
        for def in BuiltinSkills.all {
            XCTAssertFalse(def.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                           "内置 skill \(def.id) 的 content 不能为空")
        }
    }

    func test_builtins_allHaveNonEmptyName() {
        for def in BuiltinSkills.all {
            XCTAssertFalse(def.name.isEmpty, "内置 skill \(def.id) 的 name 不能为空")
        }
    }

    func test_builtins_commandsHaveUniqueNamesWithinSkill() {
        for def in BuiltinSkills.all {
            let names = def.commands.map(\.name)
            let unique = Set(names)
            XCTAssertEqual(names.count, unique.count,
                           "内置 skill \(def.id) 的 command name 在 skill 内必须唯一")
        }
    }

    func test_builtins_commandsHaveNonEmptyTrigger() {
        for def in BuiltinSkills.all {
            for cmd in def.commands {
                XCTAssertFalse(cmd.trigger.isEmpty,
                               "skill \(def.id) 的 command \(cmd.name) trigger 不能为空")
            }
        }
    }

    func test_builtins_htmlBeautifier_hasCommands() {
        let def = BuiltinSkills.htmlBeautifier
        XCTAssertFalse(def.commands.isEmpty, "htmlBeautifier 应有至少一个 command")
    }

    func test_builtins_reviewHelper_hasCommands() {
        let def = BuiltinSkills.reviewHelper
        XCTAssertFalse(def.commands.isEmpty, "reviewHelper 应有至少一个 command")
    }

    func test_pluginManager_loadsBuiltinCommands() async {
        let pm = PluginManager()
        await pm.reloadAll()

        let htmlSkill = pm.skills.first { $0.id == BuiltinSkills.ID.htmlBeautifier }
        XCTAssertNotNil(htmlSkill, "htmlBeautifier 应已加载")
        XCTAssertFalse(htmlSkill?.commands.isEmpty ?? true,
                       "htmlBeautifier 加载后应携带 commands")
    }

    func test_pluginManager_buildinCount_matchesAll() async {
        let pm = PluginManager()
        await pm.reloadAll()

        let builtinCount = pm.skills.filter { $0.source == .builtin }.count
        XCTAssertEqual(builtinCount, BuiltinSkills.all.count,
                       "PluginManager 加载的内置 skill 数量应与 BuiltinSkills.all 一致")
    }

    func test_builtins_idConstants_matchAllIDs() {
        // 确保 ID 枚举里的所有常量都有对应的 skill 在 all 里
        let allIDs: Set<String> = Set(BuiltinSkills.all.map(\.id))
        XCTAssertTrue(allIDs.contains(BuiltinSkills.ID.htmlBeautifier))
        XCTAssertTrue(allIDs.contains(BuiltinSkills.ID.inlineEditor))
        XCTAssertTrue(allIDs.contains(BuiltinSkills.ID.mermaidDiagram))
        XCTAssertTrue(allIDs.contains(BuiltinSkills.ID.weeklyReport))
        XCTAssertTrue(allIDs.contains(BuiltinSkills.ID.apiDocWriter))
        XCTAssertTrue(allIDs.contains(BuiltinSkills.ID.codeCommenter))
        XCTAssertTrue(allIDs.contains(BuiltinSkills.ID.techDesign))
        XCTAssertTrue(allIDs.contains(BuiltinSkills.ID.reviewHelper))
    }

    // MARK: - Command 解析（SKILL.md frontmatter）

    /// 手动技能的 commands 多字段（trigger/icon/tools/allowedCommands）必须完整解析，
    /// 多行列表形式的 allowedCommands 也要逐条收齐。
    func test_extractCommands_parsesFullCommandFields() async throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("meditor-skill-cmd-\(UUID().uuidString)", isDirectory: true)
        let dir = base.appendingPathComponent("cmd-skill", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let md = """
        ---
        name: cmd-skill
        description: 带命令的测试技能
        commands:
          - name: gen_commit
            trigger: 生成 Commit
            icon: arrow.triangle.branch
            description: 运行 git diff 并生成 commit message
            tools: [run_command]
            allowedCommands:
              - git status
              - git diff
              - git log
        ---

        正文。
        """
        try md.write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let pm = PluginManager()
        XCTAssertTrue(pm.addManual(skillMDURL: dir))
        await pm.reloadAll()

        let cmd = pm.skills.first { $0.source == .manual }?.commands.first
        XCTAssertEqual(cmd?.name, "gen_commit")
        XCTAssertEqual(cmd?.trigger, "生成 Commit")
        XCTAssertEqual(cmd?.icon, "arrow.triangle.branch")
        XCTAssertEqual(cmd?.allowedTools, ["run_command"])
        XCTAssertEqual(cmd?.allowedCommands, ["git status", "git diff", "git log"])
    }

    /// 同一 skill 内多个 command 都要解析出来，不能只保留第一个。
    func test_extractCommands_parsesMultipleCommands() async throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("meditor-skill-multi-\(UUID().uuidString)", isDirectory: true)
        let dir = base.appendingPathComponent("multi-cmd", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let md = """
        ---
        name: multi-cmd
        description: 多命令测试
        commands:
          - name: first
            trigger: 第一个
            tools: [read_document]
          - name: second
            trigger: 第二个
            tools: [read_document, create_file]
        ---

        正文。
        """
        try md.write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let pm = PluginManager()
        XCTAssertTrue(pm.addManual(skillMDURL: dir))
        await pm.reloadAll()

        let commands = pm.skills.first { $0.source == .manual }?.commands ?? []
        XCTAssertEqual(commands.map(\.name), ["first", "second"])
        XCTAssertEqual(commands.map(\.trigger), ["第一个", "第二个"])
        XCTAssertEqual(commands.last?.allowedTools, ["read_document", "create_file"])
    }

    // MARK: - Gallery 技能

    func test_gallery_allHaveUniqueIDsAndNonEmptyContent() {
        let ids = CuratedSkillGallery.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "Gallery 技能 id 必须唯一")
        for def in CuratedSkillGallery.all {
            XCTAssertFalse(def.name.isEmpty, "Gallery 技能 \(def.id) name 不能为空")
            XCTAssertFalse(def.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                           "Gallery 技能 \(def.id) content 不能为空")
        }
    }

    /// 旗舰技能（git 提交助手、会议纪要）安装后 frontmatter 里的 commands 必须完整保留。
    func test_gallery_flagshipSkills_commandsSurviveInstall() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("meditor-gallery-\(UUID().uuidString)", isDirectory: true)
        let pm = PluginManager()
        for def in [CuratedSkillGallery.gitCommitHelper, CuratedSkillGallery.meetingNotes] {
            let result = await SkillInstaller.install(def, into: dir, pluginManager: pm)
            guard case .installed = result else {
                XCTFail("\(def.id) 安装失败")
                return
            }
        }

        // 手动技能的 name 取自安装目录名（folderName），不是 frontmatter 里的 name
        let git = pm.skills.first {
            $0.skillPath.deletingLastPathComponent().lastPathComponent
                == CuratedSkillGallery.gitCommitHelper.folderName
        }
        XCTAssertEqual(git?.commands.first?.trigger, "生成 Commit")
        XCTAssertEqual(git?.commands.first?.allowedTools, ["run_command"])
        XCTAssertFalse(git?.commands.first?.allowedCommands.isEmpty ?? true,
                       "git 提交助手的 allowedCommands 白名单不能在解析中丢失")

        let meeting = pm.skills.first {
            $0.skillPath.deletingLastPathComponent().lastPathComponent
                == CuratedSkillGallery.meetingNotes.folderName
        }
        XCTAssertFalse(meeting?.commands.isEmpty ?? true, "会议纪要技能应提供整理命令")
    }

    // MARK: - Plugin Discovery

    func test_addSkills_pluginStructure_discoversNestedSkills() async throws {
        // 插件结构：<plugin>/skills/<name>/SKILL.md（如 sea-publish）
        let plugin = FileManager.default.temporaryDirectory
            .appendingPathComponent("meditor-plugin-\(UUID().uuidString)", isDirectory: true)
        let skillsDir = plugin.appendingPathComponent("skills", isDirectory: true)
        for name in ["sea-publish", "other-skill"] {
            let dir = skillsDir.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try "---\nname: \(name)\ndescription: d\n---\n# \(name)\n"
                .write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        }
        // 顶层无 SKILL.md，但有 scripts/ 等
        try FileManager.default.createDirectory(at: plugin.appendingPathComponent("scripts"), withIntermediateDirectories: true)

        let pm = PluginManager()
        let count = pm.addSkills(from: plugin)
        XCTAssertEqual(count, 2, "应从插件 skills/*/SKILL.md 发现 2 个技能")

        await pm.reloadAll()
        XCTAssertEqual(pm.skills.filter { $0.source == .manual }.count, 2)
    }
}
