import XCTest
@testable import MEditor

/// 旗舰技能 golden 测试集：会议纪要 / 工作汇报 / Git 提交助手。
///
/// 无真实模型可用，本套件只断言**离线可验证**的部分：
/// 1. 技能内容契约：prompt 必须包含输出格式、语言要求、长度/风格约束（防 prompt 悄悄退化）。
/// 2. 输入样本 → 质量断言：fixture 样本的特征必须有对应的 prompt 指令兜底
///    （如样本含"下周三" → prompt 必须要求相对时间换算）。
/// 3. prompt 组装完整性：builtin 经 enabledSkillsPrompt、gallery 经安装 + userSkillsPrompt
///    后内容完整、SKILL_DIR 注入正确、commands 解析正确、无 {{ }} 模板占位符残留。
///
/// 断言只用结构/关键词比对，不依赖样本的完整句子匹配，locale 无关。
@MainActor
final class FlagshipSkillGoldenTests: XCTestCase {

    // MARK: - Fixture 加载

    private static let fixturesDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()                       // Tests/MEditorTests
        .appendingPathComponent("Fixtures/FlagshipSkills", isDirectory: true)

    private func fixture(_ name: String,
                         file: StaticString = #filePath, line: UInt = #line) throws -> String {
        let url = Self.fixturesDir.appendingPathComponent(name)
        guard let content = try? String(contentsOf: url, encoding: .utf8), !content.isEmpty else {
            XCTFail("fixture 缺失或为空: \(name)", file: file, line: line)
            return ""
        }
        return content
    }

    // MARK: - 环境清理（与 PluginManagerTests 共享 UserDefaults key）

    private var tempDirs: [URL] = []

    private func cleanDefaults() {
        UserDefaults.standard.removeObject(forKey: "MEditor.pluginManualSkills")
        UserDefaults.standard.removeObject(forKey: "MEditor.pluginSkillStates")
    }

    override func setUp() { super.setUp(); cleanDefaults() }

    override func tearDown() {
        cleanDefaults()
        for dir in tempDirs {
            try? FileManager.default.removeItem(at: dir)
        }
        tempDirs = []
        super.tearDown()
    }

    /// 把 gallery 技能写入临时目录（模拟安装落盘），返回技能根目录（含 SKILL.md）。
    private func stageGallerySkill(_ skill: GallerySkillDef) throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("meditor-golden-tests-\(UUID().uuidString)", isDirectory: true)
        let dir = base.appendingPathComponent(skill.folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try skill.content.write(to: dir.appendingPathComponent("SKILL.md"),
                                atomically: true, encoding: .utf8)
        tempDirs.append(base)
        return dir
    }

    private func assertContains(_ text: String, _ keywords: [String],
                                _ label: String,
                                file: StaticString = #filePath, line: UInt = #line) {
        for keyword in keywords {
            XCTAssertTrue(text.contains(keyword),
                          "\(label) 缺少关键词: \(keyword)", file: file, line: line)
        }
    }

    // MARK: - Fixture 完整性

    func testFixtures_allSamplesPresentAndNonEmpty() throws {
        let names = [
            "meeting_notes_zh_messy.md", "meeting_notes_en_messy.md", "meeting_notes_mixed_sparse.md",
            "weekly_zh_daily_logs.md", "weekly_en_daily_logs.md", "weekly_undated_sparse.md",
            "git_diff_feat.diff", "git_diff_fix.diff", "git_diff_breaking.diff",
        ]
        for name in names {
            let content = try fixture(name)
            XCTAssertGreaterThan(content.count, 50, "\(name) 内容过短，不像真实样本")
        }
    }

    // MARK: - 1. 会议纪要：内容契约

    func testContract_meetingNotes_promptCoversFormatLanguageStyle() {
        let skill = CuratedSkillGallery.meetingNotes
        let content = skill.content

        // 输出格式要求：结构化纪要骨架（要点/决议/行动项/负责人）
        assertContains(content, ["## 输出格式", "讨论要点", "决议事项", "行动项", "负责人"],
                       "\(skill.id) 输出格式")
        // 语言要求：跟随输入语言
        assertContains(content, ["输出语言跟随输入"], "\(skill.id) 语言要求")
        // 长度/风格约束：客观中立、结论性表述、不编造、只输出正文
        assertContains(content, ["客观中立", "不要编造", "只输出整理后的纪要正文"],
                       "\(skill.id) 风格约束")
        // 行动项必须带负责人与截止时间（纪要的核心价值）
        assertContains(content, ["负责人", "截止时间"], "\(skill.id) 行动项结构")
    }

    func testContract_meetingNotes_nameMatchesFrontmatter() {
        let skill = CuratedSkillGallery.meetingNotes
        XCTAssertTrue(skill.content.contains("name: \(skill.name)"),
                      "\(skill.id) frontmatter name 应与 def.name 一致（安装判重依赖 name）")
        XCTAssertTrue(skill.content.contains("description:"), "\(skill.id) frontmatter 缺 description")
    }

    // MARK: - 1. 工作汇报：内容契约

    func testContract_weeklyReport_promptCoversFormatLanguageStyle() {
        let content = BuiltinSkills.weeklyReport.content

        // 输出格式要求：完成/进行中/风险/计划四段结构
        assertContains(content, ["## 汇报结构", "本周完成", "进行中", "下周计划", "风险"],
                       "weeklyReport 输出格式")
        // 语言要求：跟随输入语言
        assertContains(content, ["输出语言跟随输入"], "weeklyReport 语言要求")
        // 长度/风格约束：一屏以内、每条不超过两句、量化、只输出正文
        assertContains(content, ["一屏以内", "不超过两句话", "量化", "只输出汇报正文"],
                       "weeklyReport 长度/风格约束")
    }

    func testContract_weeklyReport_contentIsSharedPromptSingleSource() {
        // macOS/iOS 双端共享：BuiltinSkills 必须直接引用 SharedSkillPrompts，禁止分叉改写
        XCTAssertEqual(BuiltinSkills.weeklyReport.content, SharedSkillPrompts.weeklyReport,
                       "weeklyReport 应引用 SharedSkillPrompts（双端唯一文本来源）")
    }

    // MARK: - 1. Git 提交助手：内容契约

    func testContract_gitCommitHelper_promptCoversFormatLanguageStyle() {
        let skill = CuratedSkillGallery.gitCommitHelper
        let content = skill.content

        // 输出格式要求：Conventional Commits 骨架 + type 枚举
        assertContains(content, ["Conventional Commits", "<type>(<scope>): <subject>", "feat", "fix"],
                       "\(skill.id) 输出格式")
        // 语言要求：与仓库近期提交语言一致
        assertContains(content, ["语言", "近期提交"], "\(skill.id) 语言要求")
        // 长度约束：subject ≤ 72 字符
        assertContains(content, ["72"], "\(skill.id) 长度约束")
        // 风格约束：只输出 message 本身；破坏性变更必须写 footer
        assertContains(content, ["只输出 commit message 本身", "BREAKING CHANGE"],
                       "\(skill.id) 风格约束")
    }

    func testContract_gitCommitHelper_nameMatchesFrontmatter() {
        let skill = CuratedSkillGallery.gitCommitHelper
        XCTAssertTrue(skill.content.contains("name: \(skill.name)"),
                      "\(skill.id) frontmatter name 应与 def.name 一致")
    }

    // MARK: - 2. 输入样本 → 质量断言（会议纪要）

    func testGolden_meetingNotes_zhSample_relativeDatesAndOwnersCoveredByPrompt() throws {
        let sample = try fixture("meeting_notes_zh_messy.md")
        let prompt = CuratedSkillGallery.meetingNotes.content

        // 样本特征：含相对时间"下周三"和具体日期锚点
        XCTAssertTrue(sample.contains("下周三"), "样本应包含相对时间表达")
        // prompt 必须要求相对时间换算为具体日期
        assertContains(prompt, ["相对时间"], "会议纪要对相对时间的处理指令")

        // 样本特征：行动项归属口语化（"小李说他来催"）
        XCTAssertTrue(sample.contains("小李"), "样本应包含口语化归属")
        // prompt 必须要求补全负责人，无法确定的标"待定"而非留空
        assertContains(prompt, ["负责人", "待定"], "会议纪要对行动项归属的处理指令")

        // 样本特征：有未达成一致的议题（移动端是否一起发）
        assertContains(prompt, ["待定 & 下次会议"], "会议纪要应保留待定议题章节")
    }

    func testGolden_meetingNotes_enSample_languageFollowsInput() throws {
        let sample = try fixture("meeting_notes_en_messy.md")
        XCTAssertTrue(sample.contains("next wednesday"), "英文样本应包含英文相对时间")
        XCTAssertTrue(sample.contains("decided"), "英文样本应包含决议性陈述")

        // 英文输入 → prompt 必须声明语言跟随输入（而非固定中文输出）
        assertContains(CuratedSkillGallery.meetingNotes.content, ["输出语言跟随输入"],
                       "会议纪要语言指令")
    }

    func testGolden_meetingNotes_mixedSparseSample_noFabrication() throws {
        let sample = try fixture("meeting_notes_mixed_sparse.md")
        // 样本特征：无明确会议时间/参会人/记录人
        XCTAssertFalse(sample.contains("时间"), "稀疏样本不应自带时间字段")
        XCTAssertFalse(sample.contains("参会人"), "稀疏样本不应自带参会人字段")

        let prompt = CuratedSkillGallery.meetingNotes.content
        // prompt 必须要求：原文没有的字段留空/标"无"，不编造
        assertContains(prompt, ["不要编造", "留空"], "会议纪要对缺失信息的处理指令")
        // 中英混合输入 → 以主要语言为准
        assertContains(prompt, ["主要语言"], "会议纪要对混合语言的处理指令")
    }

    // MARK: - 2. 输入样本 → 质量断言（工作汇报）

    func testGolden_weeklyReport_zhSample_dateRangeInferenceCoveredByPrompt() throws {
        let sample = try fixture("weekly_zh_daily_logs.md")
        let prompt = BuiltinSkills.weeklyReport.content

        // 样本特征：日报条目带 ISO 日期，可推断周报时间范围
        XCTAssertTrue(sample.contains("2026-08-17"), "样本应包含可推断时间范围的日期")
        // prompt 必须要求把时间范围写进标题（YYYY-MM-DD 格式）
        assertContains(prompt, ["YYYY-MM-DD"], "周报对时间范围标题的格式指令")
        // 样本含量化数据（1.8s→1.2s、PR 号）→ prompt 必须要求量化
        XCTAssertTrue(sample.contains("1.8s"), "样本应包含可量化条目")
        assertContains(prompt, ["量化"], "周报对量化的要求")
    }

    func testGolden_weeklyReport_enSample_languageFollowsInput() throws {
        let sample = try fixture("weekly_en_daily_logs.md")
        XCTAssertTrue(sample.contains("PR #412"), "英文样本应包含交付物条目")

        assertContains(BuiltinSkills.weeklyReport.content, ["输出语言跟随输入"],
                       "周报语言指令")
    }

    func testGolden_weeklyReport_undatedSparseSample_placeholderInsteadOfFabrication() throws {
        let sample = try fixture("weekly_undated_sparse.md")
        // 样本特征：无任何 ISO 日期、无量化数据
        XCTAssertFalse(sample.contains("2026-"), "稀疏样本不应包含日期")
        XCTAssertFalse(sample.contains("%"), "稀疏样本不应包含量化数据")

        let prompt = BuiltinSkills.weeklyReport.content
        // 推断不出时间范围 → 保留占位，不编造
        assertContains(prompt, ["推断不出", "占位"], "周报对无日期输入的处理指令")
        // 原文没有的信息 → 归入"进行中"或留空，不虚构成果
        assertContains(prompt, ["不要编造"], "周报对缺信息输入的处理指令")
    }

    // MARK: - 2. 输入样本 → 质量断言（Git 提交助手）

    func testGolden_gitCommit_featDiff_workflowCoversStagedDiff() throws {
        let sample = try fixture("git_diff_feat.diff")
        // 样本特征：新增文件的标准 staged diff
        XCTAssertTrue(sample.contains("new file mode"), "feat 样本应包含新文件")
        XCTAssertTrue(sample.contains("diff --git"), "feat 样本应是标准 git diff 格式")

        let prompt = CuratedSkillGallery.gitCommitHelper.content
        // prompt 工作流必须先查暂存区 diff，且限制只能用 git 只读命令
        assertContains(prompt, ["git diff --staged", "git status", "git log"],
                       "git 助手工作流指令")
        assertContains(prompt, ["feat"], "feat 样本应对应 feat type")
    }

    func testGolden_gitCommit_fixDiff_fixTypeAndSubjectRulesCoveredByPrompt() throws {
        let sample = try fixture("git_diff_fix.diff")
        XCTAssertTrue(sample.contains("standardizedFileURL"), "fix 样本应包含修复点")

        let prompt = CuratedSkillGallery.gitCommitHelper.content
        assertContains(prompt, ["fix"], "fix 样本应对应 fix type")
        // subject 规则：动词开头、结尾不加句号
        assertContains(prompt, ["动词"], "git 助手 subject 措辞规则")
    }

    func testGolden_gitCommit_breakingDiff_breakingChangeFooterCoveredByPrompt() throws {
        let sample = try fixture("git_diff_breaking.diff")
        // 样本特征：公开协议方法签名变更（破坏性）
        XCTAssertTrue(sample.contains("FilePickerServiceProtocol"), "breaking 样本应变更公开协议")
        XCTAssertTrue(sample.contains("-    func pickFiles(allowMultiple: Bool) -> [URL]"),
                      "breaking 样本应删除旧签名")

        let prompt = CuratedSkillGallery.gitCommitHelper.content
        // prompt 必须要求破坏性变更写 BREAKING CHANGE footer
        assertContains(prompt, ["BREAKING CHANGE", "footer"],
                       "git 助手对破坏性变更的处理指令")
        // 一次提交含多个独立变更 → 提示拆分（breaking 样本跨协议+实现两个关注点）
        assertContains(prompt, ["拆分"], "git 助手对多变更提交的处理指令")
    }

    // MARK: - 3. Prompt 组装完整性（builtin）

    func testAssembly_weeklyReport_includedVerbatimInEnabledSkillsPrompt() async {
        let pm = PluginManager()
        await pm.reloadAll()

        let prompt = pm.enabledSkillsPrompt()
        XCTAssertTrue(prompt.contains("## Skill: 工作汇报"), "组装后的 prompt 应有技能标题")
        // 技能正文完整注入（frontmatter + 汇报结构都在）
        XCTAssertTrue(prompt.contains(BuiltinSkills.weeklyReport.content),
                      "weeklyReport 正文应原样注入系统 prompt")
        // 输入注入模拟：样本作为用户消息拼接后原样保留
        let sample = try? fixture("weekly_zh_daily_logs.md")
        let assembled = prompt + "\n\n" + (sample ?? "")
        XCTAssertTrue(assembled.contains(sample ?? ""), "输入样本应原样进入消息")
    }

    // MARK: - 3. Prompt 组装完整性（gallery：安装 → 解析 → 注入）

    func testAssembly_gallerySkills_installRoundTrip_injectsSkillDirAndParsesCommands() async throws {
        let meetingDir = try stageGallerySkill(CuratedSkillGallery.meetingNotes)
        let gitDir     = try stageGallerySkill(CuratedSkillGallery.gitCommitHelper)

        let pm = PluginManager()
        XCTAssertTrue(pm.addManual(skillMDURL: meetingDir), "meeting-notes 应添加成功")
        XCTAssertTrue(pm.addManual(skillMDURL: gitDir), "git-commit-helper 应添加成功")
        await pm.reloadAll()

        XCTAssertTrue(pm.loadErrors.isEmpty, "旗舰技能 SKILL.md 解析不应报错: \(pm.loadErrors)")

        // ── commands 解析（frontmatter → SkillCommand 是技能链路上唯一的结构化解析步骤）
        let gitSkill = try XCTUnwrap(pm.skills.first { $0.name == "git-commit-helper" },
                                     "git-commit-helper 应被解析加载")
        XCTAssertEqual(gitSkill.commands.count, 1, "git-commit-helper 应解析出 1 个 command")
        let genCommit = gitSkill.commands[0]
        XCTAssertEqual(genCommit.name, "gen_commit")
        XCTAssertEqual(genCommit.allowedTools, ["run_command"], "gen_commit 应只允许 run_command")
        XCTAssertEqual(genCommit.allowedCommands, ["git status", "git diff", "git log"],
                       "gen_commit 的 allowedCommands 应与 frontmatter 一致（沙箱放行白名单）")

        let meetingSkill = try XCTUnwrap(pm.skills.first { $0.name == "meeting-notes" },
                                         "meeting-notes 应被解析加载")
        XCTAssertEqual(meetingSkill.commands.count, 1, "meeting-notes 应解析出 1 个 command")
        XCTAssertEqual(meetingSkill.commands[0].name, "organize")
        XCTAssertEqual(meetingSkill.commands[0].allowedTools, ["read_document", "patch_document"],
                       "organize 应只允许读文档+回写")

        // ── SKILL_DIR 变量注入：占位符必须被真实安装路径替换。
        // 注：bookmark 解析可能返回 /private/var 真实路径（与 temporaryDirectory 的
        // /var 符号链接形式不同），因此按行尾目录名断言而非整路径相等。
        let prompt = pm.userSkillsPrompt()
        let skillDirLines = prompt.components(separatedBy: "\n")
            .filter { $0.hasPrefix("SKILL_DIR = /") }
        XCTAssertEqual(skillDirLines.count, 2, "两个技能都应注入 SKILL_DIR 绝对路径")
        XCTAssertTrue(skillDirLines.contains { $0.hasSuffix("/meeting-notes") },
                      "meeting-notes 的 SKILL_DIR 应指向其安装目录，实际: \(skillDirLines)")
        XCTAssertTrue(skillDirLines.contains { $0.hasSuffix("/git-commit-helper") },
                      "git-commit-helper 的 SKILL_DIR 应指向其安装目录，实际: \(skillDirLines)")
        // 技能正文完整注入
        XCTAssertTrue(prompt.contains(CuratedSkillGallery.meetingNotes.content),
                      "meeting-notes 正文应原样注入")
        XCTAssertTrue(prompt.contains(CuratedSkillGallery.gitCommitHelper.content),
                      "git-commit-helper 正文应原样注入")
    }

    // MARK: - 3. 模板占位符残留检查

    func testAssembly_flagshipSkills_noTemplatePlaceholderResidue() async {
        // 三个旗舰技能的 prompt 文本本身不得残留 {{var}} 风格占位符
        let skills: [(String, String)] = [
            ("meeting-notes", CuratedSkillGallery.meetingNotes.content),
            ("weekly-report", BuiltinSkills.weeklyReport.content),
            ("git-commit-helper", CuratedSkillGallery.gitCommitHelper.content),
        ]
        for (label, content) in skills {
            XCTAssertFalse(content.contains("{{"), "\(label) prompt 残留 {{ 占位符")
            XCTAssertFalse(content.contains("}}"), "\(label) prompt 残留 }} 占位符")
        }
        // builtin 技能不走 SKILL_DIR 注入，正文也不应引用该占位符
        XCTAssertFalse(BuiltinSkills.weeklyReport.content.contains("SKILL_DIR"),
                       "builtin 技能不应依赖手动技能的 SKILL_DIR 注入机制")

        // 组装后的 builtin 系统 prompt 同样无残留
        let pm = PluginManager()
        await pm.reloadAll()
        let assembled = pm.enabledSkillsPrompt()
        XCTAssertFalse(assembled.contains("{{"), "builtin 组装 prompt 残留 {{ 占位符")
        XCTAssertFalse(assembled.contains("}}"), "builtin 组装 prompt 残留 }} 占位符")
    }
}
