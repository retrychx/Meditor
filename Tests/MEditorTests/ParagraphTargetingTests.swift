import XCTest
@testable import MEditor

/// ParagraphTargeting 段落定位测试：空行分隔的 Markdown 段落；偏移落在空白段时
/// 向前回退到最近非空段落（斜杠命令删除命令文本后光标所在行的典型情形）。
final class ParagraphTargetingTests: XCTestCase {

    private func paragraph(at offset: Int, in text: String) -> String? {
        ParagraphTargeting.paragraphRange(at: offset, in: text).map { String(text[$0]) }
    }

    func testEmptyDocumentReturnsNil() {
        XCTAssertNil(ParagraphTargeting.paragraphRange(at: 0, in: ""))
    }

    func testOffsetInsideParagraph() {
        let text = "first para\n\nsecond para\n\nthird para"
        XCTAssertEqual(paragraph(at: 0, in: text), "first para")
        XCTAssertEqual(paragraph(at: 13, in: text), "second para")
        XCTAssertEqual(paragraph(at: 26, in: text), "third para")
    }

    func testOffsetAtParagraphEndBelongsToPrecedingParagraph() {
        let text = "first\n\nsecond"
        // offset 5 = "\n\n" 的第一个换行处（段尾），归前段
        XCTAssertEqual(paragraph(at: 5, in: text), "first")
    }

    func testOffsetOnBlankLineFallsBackToPreviousParagraph() {
        let text = "intro\n\n\n\nbody"
        // offset 7：空行（命令删除后的典型残留），取上一非空段
        XCTAssertEqual(paragraph(at: 7, in: text), "intro")
    }

    func testOffsetAtDocumentEnd() {
        let text = "alpha\n\nbeta"
        XCTAssertEqual(paragraph(at: text.utf16.count, in: text), "beta")
    }

    func testLeadingBlankLinesWithNoPreviousParagraph() {
        let text = "\n\nfirst"
        // 光标在最前的空白区，之前没有非空段 → nil（调用方走空目标兜底）
        XCTAssertNil(ParagraphTargeting.paragraphRange(at: 0, in: text))
    }

    func testUTF16OffsetWithCJK() {
        let text = "中文段落一\n\n中文段落二"
        // "中文段落一" 5 个 CJK 字符 = 10 个 UTF-16 单元；段 2 从偏移 12 开始
        let secondStart = ("中文段落一\n\n" as NSString).length
        XCTAssertEqual(paragraph(at: secondStart, in: text), "中文段落二")
    }

    func testContainingSelectionRange() {
        let text = "one\n\ntwo three\n\nfour"
        let range = (text as NSString).range(of: "three")
        let para = ParagraphTargeting.paragraphRange(containing: range, in: text)
        XCTAssertEqual(para.map { String(text[$0]) }, "two three")
    }
}
