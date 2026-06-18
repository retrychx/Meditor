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
        XCTAssertEqual(results.count, 3, "Should match Heading 1, 2, 3")
        XCTAssertTrue(results.allSatisfy { $0.title.hasPrefix("Heading") })
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
        XCTAssertEqual(item?.expansion.text, "# ")
        XCTAssertNil(item?.expansion.cursorOffset)
    }

    func testExpansionHeading2() {
        let item = SlashCommandHandler.allCommands.first { $0.aliases.contains("/h2") }
        XCTAssertEqual(item?.expansion.text, "## ")
    }

    func testExpansionHeading3() {
        let item = SlashCommandHandler.allCommands.first { $0.aliases.contains("/h3") }
        XCTAssertEqual(item?.expansion.text, "### ")
    }

    func testExpansionCodeBlockHasCursorOffset() {
        let item = SlashCommandHandler.allCommands.first { $0.aliases.contains("/code") }
        XCTAssertEqual(item?.expansion.text, "```\n\n```")
        XCTAssertEqual(item?.expansion.cursorOffset, 4)
    }

    func testExpansionTableText() {
        let item = SlashCommandHandler.allCommands.first { $0.aliases.contains("/table") }
        XCTAssertEqual(item?.expansion.text, "| Column | Column |\n| --- | --- |\n|  |  |")
        XCTAssertEqual(item?.expansion.cursorOffset, 36)
    }
}
