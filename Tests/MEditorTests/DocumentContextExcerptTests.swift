import XCTest
@testable import MEditor

/// DocumentContextExcerpt 预算截取测试：预算内整篇保留；超预算时保留
/// 「首部 + 光标附近段落 + 尾部」并以省略标记衔接；单段超长文档退化为行级截取。
final class DocumentContextExcerptTests: XCTestCase {

    /// 造 n 个段落，每段约 perParaTokens 个估算 token。
    private func makeDoc(paragraphs n: Int, perParaTokens: Int = 40) -> String {
        (1...n).map { "P\($0) " + String(repeating: "x", count: perParaTokens * 4) }
            .joined(separator: "\n\n")
    }

    func testWithinBudgetReturnsOriginal() {
        let content = "short document\n\nwith two paragraphs"
        let result = DocumentContextExcerpt.excerpt(content: content, cursorLine: 1)
        XCTAssertEqual(result, content)
    }

    func testOverBudgetKeepsHeadCursorAreaAndTail() {
        // 50 段 × 40 token ≈ 2000+ token，预算 600 → 触发截取
        let doc = makeDoc(paragraphs: 50)
        // 光标在第 25 段（每段 1 行 + 1 空行 → 第 25 段起始行 49）
        let result = DocumentContextExcerpt.excerpt(content: doc, cursorLine: 49, maxTokens: 600)

        XCTAssertTrue(result.contains("P1 "), "缺少首部")
        XCTAssertTrue(result.contains("P25 "), "缺少光标段")
        XCTAssertTrue(result.contains("P50 "), "缺少尾部")
        XCTAssertTrue(result.contains(DocumentContextExcerpt.ellipsis), "缺少省略标记")
        // 截掉了中段以外的段落
        XCTAssertFalse(result.contains("P10 "), "不应包含远离光标的中段")
        XCTAssertFalse(result.contains("P40 "), "不应包含远离光标的中段")
        // 结果显著短于原文
        XCTAssertLessThan(AIConversation.estimateTokens(result),
                          AIConversation.estimateTokens(doc))
    }

    func testCursorNearStartMergesWithHead() {
        let doc = makeDoc(paragraphs: 50)
        let result = DocumentContextExcerpt.excerpt(content: doc, cursorLine: 1, maxTokens: 600)
        XCTAssertTrue(result.contains("P1 "))
        XCTAssertTrue(result.contains("P50 "))
        // 光标段在首部覆盖范围内：省略标记至多出现一次（尾部之前）
        let ellipsisCount = result.components(separatedBy: DocumentContextExcerpt.ellipsis).count - 1
        XCTAssertLessThanOrEqual(ellipsisCount, 1)
    }

    func testNilCursorFallsBackToMiddle() {
        let doc = makeDoc(paragraphs: 50)
        let result = DocumentContextExcerpt.excerpt(content: doc, cursorLine: nil, maxTokens: 600)
        XCTAssertTrue(result.contains("P1 "))
        XCTAssertTrue(result.contains("P50 "))
        XCTAssertTrue(result.contains("P25 "), "nil 光标应围绕文档中段")
    }

    func testSingleGiantParagraphFallsBackToLineLevel() {
        // 一个段落 200 行，每行约 25 token → 超预算；无空行可切
        let line = String(repeating: "y", count: 100)
        let doc = (1...200).map { "L\($0) " + line }.joined(separator: "\n")
        let result = DocumentContextExcerpt.excerpt(content: doc, cursorLine: 100, maxTokens: 800)
        XCTAssertTrue(result.contains("L1 "), "缺少首行")
        XCTAssertTrue(result.contains("L100 "), "缺少光标行")
        XCTAssertTrue(result.contains("L200 "), "缺少尾行")
        XCTAssertTrue(result.contains(DocumentContextExcerpt.ellipsis))
        XCTAssertFalse(result.contains("L50 "))
    }

    func testEllipsisOnlyBetweenKeptRegions() {
        let doc = makeDoc(paragraphs: 50)
        let result = DocumentContextExcerpt.excerpt(content: doc, cursorLine: 49, maxTokens: 600)
        // 省略标记不应出现在开头或结尾（首尾区总是被保留）
        XCTAssertFalse(result.hasPrefix(DocumentContextExcerpt.ellipsis))
        XCTAssertFalse(result.hasSuffix(DocumentContextExcerpt.ellipsis))
    }

    func testFirstParagraphOverBudgetFallsBackToLineLevel() {
        // 首段 300 行（数千 token），单段即远超首部预算（600/5=120）：
        // 段级保留会整段注入使预算失效，应退化为该段的行级截取
        let giantHead = (1...300).map { "H\($0) " + String(repeating: "x", count: 60) }
            .joined(separator: "\n")
        let rest = makeDoc(paragraphs: 40)
        let doc = giantHead + "\n\n" + rest
        let result = DocumentContextExcerpt.excerpt(content: doc, cursorLine: 1, maxTokens: 600)

        XCTAssertTrue(result.contains("H1 "), "首段开头应保留")
        XCTAssertTrue(result.contains("H300 "), "首段结尾应保留（行级截取的尾部）")
        XCTAssertFalse(result.contains("H150 "), "首段中段不应整段注入")
        XCTAssertTrue(result.contains("P40 "), "文档尾部应保留")
        XCTAssertTrue(result.contains(DocumentContextExcerpt.ellipsis))
        XCTAssertLessThanOrEqual(AIConversation.estimateTokens(result), 600 + 10,
                                 "总量应收敛到预算附近（原文数千 token）")
    }

    func testLastParagraphOverBudgetFallsBackToLineLevel() {
        let rest = makeDoc(paragraphs: 40)
        let giantTail = (1...300).map { "T\($0) " + String(repeating: "x", count: 60) }
            .joined(separator: "\n")
        let doc = rest + "\n\n" + giantTail
        let result = DocumentContextExcerpt.excerpt(content: doc, cursorLine: 1, maxTokens: 600)

        XCTAssertTrue(result.contains("P1 "), "文档首部应保留")
        XCTAssertTrue(result.contains("T300 "), "尾段结尾应保留")
        XCTAssertFalse(result.contains("T150 "), "尾段中段不应整段注入")
        XCTAssertLessThanOrEqual(AIConversation.estimateTokens(result), 600 + 10)
    }

    func testSingleGiantLineHardCappedByTotalBudget() {
        // 单行上万字符：行级截取保首行不检查预算，需总量兜底校验封顶
        let doc = String(repeating: "x", count: 10_000)
        let result = DocumentContextExcerpt.excerpt(content: doc, cursorLine: 1, maxTokens: 600)

        XCTAssertLessThan(result.count, doc.count)
        XCTAssertTrue(result.contains(DocumentContextExcerpt.ellipsis))
        XCTAssertLessThanOrEqual(AIConversation.estimateTokens(result), 600)
    }
}
