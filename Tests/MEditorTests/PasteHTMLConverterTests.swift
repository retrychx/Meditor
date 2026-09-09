import XCTest
@testable import MEditor

/// 粘贴路径的 HTML → Markdown 转换测试。
/// 转换器本体（mdH2M）与导出共用 HTMLToMarkdownJS，这里覆盖：
/// 清理函数、HTML flavor 判定，以及一条端到端转换（离屏 WKWebView）。
@MainActor
final class PasteHTMLConverterTests: XCTestCase {

    // MARK: - cleanConvertedMarkdown

    func testCleanTrimsTrailingSpacesAndCollapsesBlankLines() {
        let raw = "line one   \n\n\n\nline two  \n"
        let cleaned = HTMLToMarkdownJS.cleanConvertedMarkdown(raw)
        XCTAssertEqual(cleaned, "line one\n\nline two")
    }

    func testCleanTrimsLeadingAndTrailingWhitespace() {
        let raw = "\n\n  # Title  \n\n"
        let cleaned = HTMLToMarkdownJS.cleanConvertedMarkdown(raw)
        XCTAssertEqual(cleaned, "# Title")
    }

    func testCleanPreservesSingleBlankLine() {
        let raw = "a\n\nb"
        XCTAssertEqual(HTMLToMarkdownJS.cleanConvertedMarkdown(raw), "a\n\nb")
    }

    // MARK: - containsMarkup

    func testContainsMarkupDetectsTags() {
        XCTAssertTrue(EditorCoordinator.containsMarkup("<html><body><p>hi</p></body></html>"))
        XCTAssertTrue(EditorCoordinator.containsMarkup("<b>bold</b>"))
    }

    func testContainsMarkupRejectsPlainTextWrappedHTML() {
        XCTAssertFalse(EditorCoordinator.containsMarkup("just plain text"))
        XCTAssertFalse(EditorCoordinator.containsMarkup(""))
        XCTAssertFalse(EditorCoordinator.containsMarkup("2 < 3 and 5 > 4"))
    }

    // MARK: - End-to-end conversion（离屏 WKWebView）

    func testConvertHeadingsListsAndLinks() async throws {
        let html = """
        <html><body>
        <h2>Title</h2>
        <p>Hello <strong>world</strong> <a href="https://example.com">link</a></p>
        <ul><li>one</li><li>two</li></ul>
        </body></html>
        """
        let markdown = try await convert(html)
        XCTAssertTrue(markdown.contains("## Title"), "got: \(markdown)")
        XCTAssertTrue(markdown.contains("<strong>world</strong>"), "got: \(markdown)")
        XCTAssertTrue(markdown.contains("[link](https://example.com)"), "got: \(markdown)")
        XCTAssertTrue(markdown.contains("- one"), "got: \(markdown)")
        XCTAssertTrue(markdown.contains("- two"), "got: \(markdown)")
    }

    func testConvertTableAndCodeBlock() async throws {
        let html = """
        <html><body>
        <table><tr><th>A</th><th>B</th></tr><tr><td>1</td><td>2</td></tr></table>
        <pre><code class="language-swift">let x = 1</code></pre>
        </body></html>
        """
        let markdown = try await convert(html)
        XCTAssertTrue(markdown.contains("| A | B |"), "got: \(markdown)")
        XCTAssertTrue(markdown.contains("| 1 | 2 |"), "got: \(markdown)")
        XCTAssertTrue(markdown.contains("```swift"), "got: \(markdown)")
        XCTAssertTrue(markdown.contains("let x = 1"), "got: \(markdown)")
    }

    func testConvertBlockquote() async throws {
        let html = "<html><body><blockquote><p>quoted line</p></blockquote></body></html>"
        let markdown = try await convert(html)
        XCTAssertTrue(markdown.contains("> quoted line"), "got: \(markdown)")
    }

    private func convert(_ html: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            PasteHTMLConverter.shared.convert(html: html) { markdown in
                if let markdown {
                    continuation.resume(returning: markdown)
                } else {
                    continuation.resume(throwing: XCTestError(.failureWhileWaiting))
                }
            }
        }
    }
}
