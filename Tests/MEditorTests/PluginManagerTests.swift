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
