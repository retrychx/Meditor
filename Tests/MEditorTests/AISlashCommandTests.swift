import XCTest
@testable import MEditor

/// 斜杠 AI 命令注册表测试：完整性、查找、prompt 构建（含参数拼接）。
/// 不断言中文文案本身（CI 英文 locale），只断言结构与不变量。
final class AISlashCommandTests: XCTestCase {

    // MARK: - 注册表完整性

    func testRegistryCoversRequiredCommands() {
        let ids = Set(AISlashCommandRegistry.all.map(\.id))
        // 命令库要求的五个新命令 + 既有 /ask + 功能 10 的 /table
        for required in ["ask", "polish", "outline", "translate", "summary", "fix", "table"] {
            XCTAssertTrue(ids.contains(required), "缺少命令 \(required)")
        }
    }

    func testAliasesAreUniqueAcrossRegistry() {
        var seen = Set<String>()
        for cmd in AISlashCommandRegistry.all {
            for alias in cmd.aliases {
                XCTAssertTrue(seen.insert(alias).inserted, "别名重复：\(alias)")
            }
        }
    }

    func testLookupByAliasIsCaseInsensitive() {
        XCTAssertEqual(AISlashCommandRegistry.command(forAlias: "/polish")?.id, "polish")
        XCTAssertEqual(AISlashCommandRegistry.command(forAlias: "/POLISH")?.id, "polish")
        XCTAssertEqual(AISlashCommandRegistry.command(forAlias: "/ai-continue")?.id, "continue")
        XCTAssertNil(AISlashCommandRegistry.command(forAlias: "/nonexistent"))
    }

    func testLocalizationKeysResolveForAllCommands() {
        // L() miss 时返回 key 本身——断言 title/subtitle 不以 "slash." 开头即为命中
        for cmd in AISlashCommandRegistry.all {
            XCTAssertFalse(cmd.title.hasPrefix("slash."), "\(cmd.id) 缺少 title 本地化")
            XCTAssertFalse(cmd.subtitle.hasPrefix("slash."), "\(cmd.id) 缺少 subtitle 本地化")
        }
    }

    // MARK: - 输出去向分类

    func testOutputRouting() {
        // 只读命令走聊天气泡
        XCTAssertEqual(AISlashCommandRegistry.command(id: "summary")?.output, .chatBubble)
        XCTAssertEqual(AISlashCommandRegistry.command(id: "ask")?.output, .chatBubble)
        // 写文档命令走 diff 确认写回
        for id in ["polish", "outline", "translate", "fix", "table"] {
            XCTAssertEqual(AISlashCommandRegistry.command(id: id)?.output, .diffWriteBack, id)
        }
    }

    func testScopes() {
        XCTAssertEqual(AISlashCommandRegistry.command(id: "polish")?.scope, .paragraphOrSelection)
        XCTAssertEqual(AISlashCommandRegistry.command(id: "translate")?.scope, .paragraphOrSelection)
        XCTAssertEqual(AISlashCommandRegistry.command(id: "table")?.scope, .paragraphOrSelection)
        XCTAssertEqual(AISlashCommandRegistry.command(id: "outline")?.scope, .document)
        XCTAssertEqual(AISlashCommandRegistry.command(id: "fix")?.scope, .document)
        XCTAssertEqual(AISlashCommandRegistry.command(id: "summary")?.scope, .document)
    }

    // MARK: - prompt 构建

    func testAskPromptIsArgumentVerbatim() {
        let ask = AISlashCommandRegistry.command(id: "ask")!
        XCTAssertEqual(ask.buildPrompt(.init(argument: "什么是闭包")), "什么是闭包")
        // 无参数回退占位提示（与旧实现逐字一致）
        XCTAssertEqual(ask.buildPrompt(.init()), "请回答一个问题（在此输入）：")
    }

    func testContinuePromptUsesPrecedingContextSuffix() {
        let cmd = AISlashCommandRegistry.command(id: "continue")!
        let long = String(repeating: "a", count: 2000)
        let prompt = cmd.buildPrompt(.init(precedingContext: long))
        XCTAssertTrue(prompt.hasSuffix(String(repeating: "a", count: 800)))
    }

    func testParagraphCommandsIncludeTarget() {
        for id in ["polish", "translate", "table"] {
            let cmd = AISlashCommandRegistry.command(id: id)!
            let prompt = cmd.buildPrompt(.init(target: "TARGET_BODY"))
            XCTAssertTrue(prompt.contains("TARGET_BODY"), id)
        }
    }

    func testDocumentCommandsIncludeDocument() {
        for id in ["outline", "summary"] {
            let cmd = AISlashCommandRegistry.command(id: id)!
            let prompt = cmd.buildPrompt(.init(document: "WHOLE_DOC"))
            XCTAssertTrue(prompt.contains("WHOLE_DOC"), id)
        }
    }

    func testFixPromptIncludesDiagnosticsAndDocument() {
        let cmd = AISlashCommandRegistry.command(id: "fix")!
        let prompt = cmd.buildPrompt(.init(document: "DOC", diagnostics: "ISSUE_LIST"))
        XCTAssertTrue(prompt.contains("ISSUE_LIST"))
        XCTAssertTrue(prompt.contains("DOC"))
    }

    func testArgumentAppendedForArgumentTakingCommands() {
        let polish = AISlashCommandRegistry.command(id: "polish")!
        XCTAssertTrue(polish.takesArgument)
        let prompt = polish.buildPrompt(.init(target: "T", argument: "更正式"))
        XCTAssertTrue(prompt.contains("T"))
        XCTAssertTrue(prompt.contains("更正式"))
        // 无参数时不追加空要求
        XCTAssertEqual(polish.buildPrompt(.init(target: "T")),
                       polish.buildPrompt(.init(target: "T", argument: "")))
    }

    // MARK: - /table 空目标兜底

    func testTableCommandHasSkeletonFallback() {
        let table = AISlashCommandRegistry.command(id: "table")!
        let fallback = table.emptyFallbackInsertion ?? ""
        XCTAssertTrue(fallback.contains("| --- | --- |"))
    }

    // MARK: - 菜单 item 生成

    func testMenuItemsAreGeneratedFromRegistry() {
        let aiItems = SlashCommandHandler.allCommands.filter(\.isAICommand)
        XCTAssertEqual(aiItems.count, AISlashCommandRegistry.all.count)
        // 别名与注册表一致；/table 归 AI 命令（原静态骨架已移除出目录）
        let tableItem = SlashCommandHandler.allCommands.first { $0.aliases.contains("/table") }
        XCTAssertEqual(tableItem?.aiCommandID, "table")
    }

    func testStaticCommandsKeepNoTableEntry() {
        let staticAliases = SlashCommandHandler.staticCommands.flatMap(\.aliases)
        XCTAssertFalse(staticAliases.contains("/table"))
    }

    // MARK: - 过滤（菜单匹配）

    func testFilteredCommandsMatchesLocalizedTitleAndKeywords() {
        let handler = SlashCommandHandler()
        // 别名前缀
        XCTAssertTrue(handler.filteredCommands(for: "/pol").contains { $0.aiCommandID == "polish" })
        // 参数部分不参与匹配
        XCTAssertTrue(handler.filteredCommands(for: "/polish 更正式").contains { $0.aiCommandID == "polish" })
        // 关键词（中文）
        XCTAssertTrue(handler.filteredCommands(for: "/润色").contains { $0.aiCommandID == "polish" })
        // 空 query 返回全部
        XCTAssertEqual(handler.filteredCommands(for: "/").count, SlashCommandHandler.allCommands.count)
    }
}
