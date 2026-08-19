import XCTest
@testable import MEditor

/// 复制为富文本（功能8）：粘贴板 HTML 组装、标题转义、表格边框兜底。
final class RichTextCopyServiceTests: XCTestCase {

    // MARK: - pasteboardHTML（纯字符串组装）

    func test_pasteboardHTML_wrapsBodyAndCSS() {
        let html = RichTextCopyService.pasteboardHTML(bodyHTML: "<h1>Hi</h1>", title: "Doc")
        XCTAssertTrue(html.contains("<h1>Hi</h1>"))
        XCTAssertTrue(html.contains("<style>"))
        XCTAssertTrue(html.contains("<title>Doc</title>"))
    }

    func test_pasteboardCSS_hasTableBorders() {
        // 表格边框是硬需求：贴到邮件/飞书时表格必须带框
        XCTAssertTrue(RichTextCopyService.pasteboardCSS.contains("border-collapse"))
        XCTAssertTrue(RichTextCopyService.pasteboardCSS.contains("th, td { border:"))
    }

    func test_escapeHTML_escapesSpecials() {
        XCTAssertEqual(RichTextCopyService.escapeHTML(#"a<b>&"c"#), "a&lt;b&gt;&amp;&quot;c")
    }

    // MARK: - 图片相对 src 绝对化

    func test_absolutizingImageSources_resolvesRelativeAgainstDocDir() {
        let base = URL(fileURLWithPath: "/tmp/docs", isDirectory: true)
        let html = #"<p><img src="assets/pic.png" alt="p"></p>"#
        let out = RichTextCopyService.absolutizingImageSources(in: html, baseURL: base)
        XCTAssertTrue(out.contains(#"src="file:///tmp/docs/assets/pic.png""#))
    }

    func test_absolutizingImageSources_resolvesParentAndSpacePaths() {
        let base = URL(fileURLWithPath: "/tmp/docs", isDirectory: true)
        let html = #"<img src="../shared/a b.png">"#
        let out = RichTextCopyService.absolutizingImageSources(in: html, baseURL: base)
        XCTAssertTrue(out.contains("file:///tmp/shared/a%20b.png"))
    }

    func test_absolutizingImageSources_leavesAbsoluteURLsAlone() {
        let base = URL(fileURLWithPath: "/tmp/docs", isDirectory: true)
        let html = """
        <img src="https://example.com/a.png"><img src="data:image/png;base64,AAAA">\
        <img src="file:///abs/b.png"><img src="//cdn.example.com/c.png">
        """
        let out = RichTextCopyService.absolutizingImageSources(in: html, baseURL: base)
        XCTAssertEqual(out, html)
    }

    // MARK: - HTML → 富文本

    @MainActor
    func test_makeAttributedString_parsesHeadingsAndCode() {
        let html = RichTextCopyService.pasteboardHTML(
            bodyHTML: "<h1>Title</h1><p>body <code>x=1</code></p>", title: "t")
        let attr = RichTextCopyService.makeAttributedString(fromPasteboardHTML: html)
        XCTAssertNotNil(attr)
        XCTAssertTrue(attr!.string.contains("Title"))
        XCTAssertTrue(attr!.string.contains("x=1"))
    }

    @MainActor
    func test_applyTableBorders_setsBorderWidthOnTableBlocks() {
        let html = RichTextCopyService.pasteboardHTML(
            bodyHTML: "<table><tr><th>A</th></tr><tr><td>1</td></tr></table>", title: "t")
        guard let attr = RichTextCopyService.makeAttributedString(fromPasteboardHTML: html) else {
            XCTFail("HTML 解析失败")
            return
        }
        // 找到至少一个带边框的表格块
        var borderedBlocks = 0
        attr.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: attr.length)) { value, _, _ in
            guard let style = value as? NSParagraphStyle else { return }
            for block in style.textBlocks where block is NSTextTableBlock {
                if block.width(for: .border, edge: .minX) > 0 { borderedBlocks += 1 }
            }
        }
        XCTAssertGreaterThan(borderedBlocks, 0, "表格单元格应带边框")
    }
}
