import XCTest
@testable import MEditor

final class SlashCommandTests: XCTestCase {

    private let handler = SlashCommandHandler()

    // MARK: - filteredCommands(for:)

    func testFilteredCommandsEmptyQueryReturnsAll() {
        let results = handler.filteredCommands(for: "/")
        XCTAssertEqual(results.count, SlashCommandHandler.allCommands.count)
    }

    func testFilteredCommandsHeadingKeywordReturnsOnlyHeadings() {
        let results = handler.filteredCommands(for: "/head")
        // 过滤匹配本地化标题/副标题，英文 locale 下其他命令（如 outline）也可能命中，
        // 因此只断言三个 Heading 必中、且每条结果都确实匹配查询
        XCTAssertTrue(results.contains { $0.title == "Heading 1" })
        XCTAssertTrue(results.contains { $0.title == "Heading 2" })
        XCTAssertTrue(results.contains { $0.title == "Heading 3" })
        XCTAssertTrue(results.allSatisfy {
            $0.displayTitle.lowercased().contains("head")
                || $0.displaySubtitle.lowercased().contains("head")
                || $0.keywords.contains { $0.lowercased().contains("head") }
        })
    }

    func testFilteredCommandsCaseInsensitive() {
        let lower = handler.filteredCommands(for: "/heading")
        let upper = handler.filteredCommands(for: "/HEADING")
        XCTAssertEqual(lower.count, upper.count)
        XCTAssertFalse(lower.isEmpty)
    }

    func testFilteredCommandsNoMatchReturnsEmpty() {
        let results = handler.filteredCommands(for: "/xyznothing123")
        XCTAssertTrue(results.isEmpty)
    }

    func testFilteredCommandsCodeAlias() {
        let results = handler.filteredCommands(for: "/code")
        XCTAssertTrue(results.contains { $0.title == "Code Block" })
    }

    func testFilteredCommandsKeywordSearch() {
        let results = handler.filteredCommands(for: "/checkbox")
        XCTAssertTrue(results.contains { $0.title == "Todo" })
    }

    // MARK: - SlashCommandItem

    func testSlashCommandItemUniqueIDs() {
        let ids = Set(SlashCommandHandler.allCommands.map { $0.id })
        XCTAssertEqual(ids.count, SlashCommandHandler.allCommands.count)
    }

    func testSlashCommandItemEquatableByID() {
        let a = SlashCommandHandler.allCommands[0]
        let b = SlashCommandHandler.allCommands[0]
        XCTAssertEqual(a, b)
        let c = SlashCommandHandler.allCommands[1]
        XCTAssertNotEqual(a, c)
    }

    // MARK: - SlashCommandExpansion text values

    func testExpansionHeading1() {
        let item = SlashCommandHandler.allCommands.first { $0.aliases.contains("/h1") }
        XCTAssertEqual(item?.expansion?.text, "# ")
        XCTAssertNil(item?.expansion?.cursorOffset)
    }

    func testExpansionHeading2() {
        let item = SlashCommandHandler.allCommands.first { $0.aliases.contains("/h2") }
        XCTAssertEqual(item?.expansion?.text, "## ")
    }

    func testExpansionHeading3() {
        let item = SlashCommandHandler.allCommands.first { $0.aliases.contains("/h3") }
        XCTAssertEqual(item?.expansion?.text, "### ")
    }

    func testExpansionCodeBlockHasCursorOffset() {
        let item = SlashCommandHandler.allCommands.first { $0.aliases.contains("/code") }
        XCTAssertEqual(item?.expansion?.text, "```\n\n```")
        XCTAssertEqual(item?.expansion?.cursorOffset, 4)
    }

    func testExpansionTableText() {
        // /table 已升级为 AI 命令（模型转表格，diff 确认写回）；静态两列骨架
        // 作为空目标兜底保留在注册表条目的 emptyFallbackInsertion。
        let item = SlashCommandHandler.allCommands.first { $0.aliases.contains("/table") }
        XCTAssertNil(item?.expansion)
        XCTAssertEqual(item?.aiCommandID, "table")
        XCTAssertEqual(item?.aiCommand?.emptyFallbackInsertion,
                       "| Column | Column |\n| --- | --- |\n|  |  |")
    }
}
