import XCTest
@testable import MEditor

final class MarkdownFormatterTests: XCTestCase {

    /// 去掉文末统一追加的换行，便于断言。
    private func fmt(_ s: String) -> String {
        var r = MarkdownFormatter.format(s)
        if r.hasSuffix("\n") { r.removeLast() }
        return r
    }

    func test_cjkLatinSpacing() {
        XCTAssertEqual(fmt("中文abc"), "中文 abc")
        XCTAssertEqual(fmt("abc中文"), "abc 中文")
        XCTAssertEqual(fmt("数字123个"), "数字 123 个")
    }

    func test_inlineCode_notSpacedInside() {
        // 行内代码内部不应被加空格，且原样保留
        let out = fmt("用`code中文`包裹")
        XCTAssertTrue(out.contains("`code中文`"), out)
    }

    func test_fencedCodeBlock_preserved() {
        let input = """
        正文中文abc

        ```swift
        let a = 1 // 中文abc 保持
        ```
        """
        let out = fmt(input)
        // 正文被加空格
        XCTAssertTrue(out.contains("正文中文 abc"), out)
        // 代码块内原样（不加空格）
        XCTAssertTrue(out.contains("// 中文abc 保持"), out)
    }

    func test_headingSpace() {
        XCTAssertEqual(fmt("##标题"), "## 标题")
        XCTAssertEqual(fmt("# 已有空格"), "# 已有空格")
    }

    func test_unorderedListMarker() {
        XCTAssertEqual(fmt("* item"), "- item")
        XCTAssertEqual(fmt("+ item"), "- item")
        XCTAssertEqual(fmt("- item"), "- item")
        XCTAssertEqual(fmt("***"), "***")   // 分隔线不动
    }

    func test_collapseBlankLines_and_trailingSpace() {
        XCTAssertEqual(fmt("a\n\n\n\nb"), "a\n\nb")
        XCTAssertEqual(fmt("abc   "), "abc")
    }

    func test_tableAlignment() {
        let input = """
        | a | bb |
        |---|---|
        | 1 | 222 |
        """
        let expected = """
        | a   | bb  |
        | --- | --- |
        | 1   | 222 |
        """
        XCTAssertEqual(fmt(input), expected)
    }

    func test_idempotent() {
        let input = """
        ##标题abc

        * 一项item
        +  另一项

        | a | bb |
        |---|---|
        | 1 | 222 |
        """
        let once = MarkdownFormatter.format(input)
        let twice = MarkdownFormatter.format(once)
        XCTAssertEqual(once, twice)
    }
}
