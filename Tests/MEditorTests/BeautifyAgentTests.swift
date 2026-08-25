import XCTest
@testable import MEditor

/// BeautifyAgent 的纯逻辑测试：token 覆盖块构造、消息装配（html-doc 骨架 vs 主题内联 CSS）、
/// 技能禁用时的错误路径。网络/模型调用不在此处测（走 generate 时才会触及 AIClient）。
@MainActor
final class BeautifyAgentTests: XCTestCase {

    private func makeTemplate(
        id: String,
        content: String = "<html><head><style>body{}</style></head><body></body></html>",
        ext: String = "html",
        category: TemplateCategory = .htmlTheme
    ) -> DocumentTemplate {
        DocumentTemplate(
            id: id, name: id, description: "", content: content,
            isBuiltin: true, createdAt: .distantPast, fileExtension: ext,
            category: category
        )
    }

    // MARK: - makeOverrideBlock

    func testOverrideBlock_emptyInput_returnsEmpty() {
        XCTAssertEqual(BeautifyAgent.makeOverrideBlock([:]), "")
    }

    func testOverrideBlock_singleToken_formatsCSSVariable() {
        let block = BeautifyAgent.makeOverrideBlock(["accent": "#ff0000"])
        XCTAssertEqual(block, "\n:root {\n  --accent: #ff0000;\n}")
    }

    func testOverrideBlock_multipleTokens_sortedByKey() {
        // key 排序保证输出确定（字典遍历顺序不稳定）
        let block = BeautifyAgent.makeOverrideBlock(["width": "700px", "accent": "red", "bg": "white"])
        let lines = block.split(separator: "\n").map(String.init)
        XCTAssertEqual(Array(lines[1...3]), ["  --accent: red;", "  --bg: white;", "  --width: 700px;"])
    }

    // MARK: - buildMessages：html-doc 骨架模式

    func testBuildMessages_htmlDoc_injectsOverrideBeforeStyleEnd() {
        let template = makeTemplate(
            id: "html-doc",
            content: "<html><head><style>body{color:black}</style></head><body>SLOT</body></html>"
        )
        let messages = BeautifyAgent().buildMessages(
            markdown: "# Hello", template: template,
            tokenOverrides: ["accent": "blue"], pluginManager: PluginManager()
        )

        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0].role, .system)
        XCTAssertEqual(messages[0].content, BuiltinSkills.htmlDocBeautifierContent,
                       "无附加技能时 system 应等于 htmlDocBeautifierContent 原文")

        let user = messages[1].content
        XCTAssertTrue(user.contains("# Hello"), "user 消息应包含原始 Markdown")
        guard let rootRange = user.range(of: ":root"),
              let styleEnd = user.range(of: "</style>") else {
            return XCTFail("覆盖块应注入到模板 </style> 之前，实际 user：\(user)")
        }
        XCTAssertTrue(rootRange.lowerBound < styleEnd.lowerBound,
                      ":root 覆盖块必须在 </style> 之前（确定性生效，不依赖 AI 合并）")
        XCTAssertTrue(user.contains("--accent: blue;"))
    }

    func testBuildMessages_htmlDoc_noOverride_keepsTemplateVerbatim() {
        let content = "<html><head><style>x{}</style></head><body>y</body></html>"
        let messages = BeautifyAgent().buildMessages(
            markdown: "md", template: makeTemplate(id: "html-doc", content: content),
            tokenOverrides: [:], pluginManager: PluginManager()
        )
        XCTAssertTrue(messages[1].content.contains(content), "无覆盖时模板应原样进入 user 消息")
        XCTAssertFalse(messages[1].content.contains(":root"), "无覆盖时不应注入 :root 块")
    }

    // MARK: - buildMessages：主题内联 CSS 模式

    func testBuildMessages_themeTemplate_inlinesThemeCSS() {
        let messages = BeautifyAgent().buildMessages(
            markdown: "# Hi", template: makeTemplate(id: "html-tufte"),
            tokenOverrides: [:], pluginManager: PluginManager()
        )
        let system = messages[0].content
        XCTAssertTrue(system.contains(BuiltinSkills.htmlBeautifier.content), "system 应含美化 skill 提示词")
        XCTAssertTrue(system.contains(BuiltinTemplates.tufteCSS), "tufte 模板应内联 tufte CSS")
        XCTAssertEqual(messages[1].role, .user)
        XCTAssertTrue(messages[1].content.contains("# Hi"))
    }

    func testBuildMessages_themeTemplate_appendsOverrideAfterCSS() {
        let messages = BeautifyAgent().buildMessages(
            markdown: "md", template: makeTemplate(id: "html-craft"),
            tokenOverrides: ["accent": "pink"], pluginManager: PluginManager()
        )
        let system = messages[0].content
        guard let cssRange = system.range(of: BuiltinTemplates.craftCSS) else {
            return XCTFail("system 应含主题 CSS")
        }
        // 主题 CSS 自身以 :root 开头，必须在 CSS 之后搜索覆盖块
        let overrideBlock = "\n:root {\n  --accent: pink;\n}"
        XCTAssertNotNil(system.range(of: overrideBlock, range: cssRange.upperBound..<system.endIndex),
                        "覆盖块应追加在主题 CSS 之后")
    }

    func testBuildMessages_unknownThemeID_fallsBackToCraftCSS() {
        let messages = BeautifyAgent().buildMessages(
            markdown: "md", template: makeTemplate(id: "html-unknown"),
            tokenOverrides: [:], pluginManager: PluginManager()
        )
        XCTAssertTrue(messages[0].content.contains(BuiltinTemplates.craftCSS))
    }

    // MARK: - buildMessages：附加用户技能

    func testBuildMessages_enabledUserSkill_appendedToSystem() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("meditor-beautify-\(UUID().uuidString)", isDirectory: true)
        let skillDir = dir.appendingPathComponent("extra-skill", isDirectory: true)
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        try "---\nname: extra-skill\ndescription: d\n---\n额外技能正文\n".write(
            to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8
        )
        defer { try? FileManager.default.removeItem(at: dir) }

        // addManual 会写 UserDefaults（"MEditor.pluginManualSkills"），测试后还原
        let defaults = UserDefaults.standard
        let savedManual = defaults.object(forKey: "MEditor.pluginManualSkills")
        defer {
            if let savedManual { defaults.set(savedManual, forKey: "MEditor.pluginManualSkills") }
            else { defaults.removeObject(forKey: "MEditor.pluginManualSkills") }
        }

        let pm = PluginManager()
        XCTAssertTrue(pm.addManual(skillMDURL: skillDir))
        await pm.reloadAll()

        let messages = BeautifyAgent().buildMessages(
            markdown: "md", template: makeTemplate(id: "html-craft"),
            tokenOverrides: [:], pluginManager: pm
        )
        // 断言语言无关的结构标记：SKILL_DIR 注入头部
        XCTAssertTrue(messages[0].content.contains("SKILL_DIR = "),
                      "启用中的用户技能应注入 system 消息")
        XCTAssertTrue(messages[0].content.contains(skillDir.path))
    }

    // MARK: - generate：技能禁用错误路径

    func testGenerate_beautifierDisabled_completesWithNotConfigured() async {
        let defaults = UserDefaults.standard
        let savedStates = defaults.object(forKey: "MEditor.pluginSkillStates")
        defer {
            if let savedStates { defaults.set(savedStates, forKey: "MEditor.pluginSkillStates") }
            else { defaults.removeObject(forKey: "MEditor.pluginSkillStates") }
        }

        let pm = PluginManager()
        await pm.reloadAll()
        pm.setEnabled(BuiltinSkills.ID.htmlBeautifier, enabled: false)

        var completed = false
        var resultText: String??
        var resultError: Error??
        _ = BeautifyAgent().generate(
            markdown: "# hi",
            template: makeTemplate(id: "html-craft"),
            settings: AppSettings.shared,
            pluginManager: pm,
            onChunk: { _ in XCTFail("技能禁用时不应产生流式输出") },
            onComplete: { text, error in
                completed = true
                resultText = text
                resultError = error
            }
        )

        XCTAssertTrue(completed, "禁用路径应同步完成，不走网络")
        XCTAssertNil(resultText ?? nil)
        guard case .some(.some(AIError.notConfigured)) = resultError else {
            return XCTFail("应返回 AIError.notConfigured，实际：\(String(describing: resultError))")
        }
    }
}
