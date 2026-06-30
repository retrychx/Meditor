import XCTest
@testable import MEditor

/// Tests SlashCommandExpansion values and SlashCommandItem conformances.
/// NSTextView-dependent methods (wrapSelection/toggleBold/toggleItalic/insertLink)
/// require a live AppKit run loop and are tested via manual UI testing.
final class EditorMarkdownShortcutsTests: XCTestCase {

    // MARK: - SlashCommandExpansion table-driven

    func testAllExpansionTexts() {
        let expected: [(alias: String, text: String, cursorOffset: Int?)] = [
            ("/h1",       "# ",                                          nil),
            ("/h2",       "## ",                                         nil),
            ("/h3",       "### ",                                        nil),
            ("/todo",     "- [ ] ",                                      nil),
            ("/bullet",   "- ",                                          nil),
            ("/numbered", "1. ",                                         nil),
            ("/quote",    "> ",                                          nil),
            ("/hr",       "---\n",                                       nil),
            ("/code",     "```\n\n```",                                  4),
            ("/table",    "| Column | Column |\n| --- | --- |\n|  |  |", 36),
        ]
        for row in expected {
            let item = SlashCommandHandler.allCommands.first { $0.aliases.contains(row.alias) }
            XCTAssertNotNil(item, "Missing command for alias \(row.alias)")
            XCTAssertEqual(item?.expansion?.text, row.text,
                           "Wrong expansion.text for \(row.alias)")
            XCTAssertEqual(item?.expansion?.cursorOffset, row.cursorOffset,
                           "Wrong expansion.cursorOffset for \(row.alias)")
        }
    }

    // MARK: - SlashCommandItem Identifiable

    func testSlashCommandItemHasStableID() {
        let item = SlashCommandHandler.allCommands[0]
        XCTAssertNotNil(item.id)
        // The ID is assigned at struct creation; accessing the same element twice
        // returns the same instance (value type but id is set at init).
        XCTAssertEqual(item.id, SlashCommandHandler.allCommands[0].id)
    }

    // MARK: - SlashCommandItem Equatable

    func testSameIndexItemsAreEqual() {
        let a = SlashCommandHandler.allCommands[2]
        let b = SlashCommandHandler.allCommands[2]
        XCTAssertEqual(a, b)
    }

    func testDifferentIndexItemsAreNotEqual() {
        let a = SlashCommandHandler.allCommands[0]
        let b = SlashCommandHandler.allCommands[1]
        XCTAssertNotEqual(a, b)
    }

    // MARK: - allCommands catalogue completeness

    func testAllCommandsCount() {
        XCTAssertEqual(SlashCommandHandler.allCommands.count, 14)
    }

    func testEveryCommandHasAtLeastOneAlias() {
        for item in SlashCommandHandler.allCommands {
            XCTAssertFalse(item.aliases.isEmpty, "\(item.title) has no aliases")
            XCTAssertTrue(item.aliases.allSatisfy { $0.hasPrefix("/") },
                          "\(item.title) alias missing leading /")
        }
    }
}
