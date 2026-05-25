import XCTest
@testable import MEditor

final class EditorTabTests: XCTestCase {

    func test_name_usesLastPathComponent() {
        let url = URL(fileURLWithPath: "/tmp/doc.md")
        let tab = EditorTab(url: url, content: "", language: .markdown)
        XCTAssertEqual(tab.name, "doc.md")
    }

    func test_isModified_defaultsToFalse() {
        let tab = EditorTab(url: URL(fileURLWithPath: "/tmp/a.md"), content: "", language: .markdown)
        XCTAssertFalse(tab.isModified)
    }

    func test_iconName_markdown() {
        let tab = EditorTab(url: URL(fileURLWithPath: "/tmp/a.md"), content: "", language: .markdown)
        XCTAssertEqual(tab.iconName, "doc.text")
    }

    func test_iconName_html() {
        let tab = EditorTab(url: URL(fileURLWithPath: "/tmp/a.html"), content: "", language: .html)
        XCTAssertEqual(tab.iconName, "doc.richtext")
    }

    func test_identifiable() {
        let tab = EditorTab(url: URL(fileURLWithPath: "/tmp/a.md"), content: "hi", language: .markdown)
        let tab2 = EditorTab(url: URL(fileURLWithPath: "/tmp/a.md"), content: "hi", language: .markdown)
        XCTAssertNotEqual(tab.id, tab2.id) // each tab gets unique id
    }

    func test_contentStoredCorrectly() {
        let tab = EditorTab(url: URL(fileURLWithPath: "/tmp/a.md"), content: "# Hello\nWorld", language: .markdown)
        XCTAssertEqual(tab.content, "# Hello\nWorld")
    }
}
