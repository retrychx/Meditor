import XCTest
@testable import MEditor

/// 内联编辑用的纯文本字面定位辅助（StringSearch.swift）：
/// 唯一性定位（编辑器选区失效兜底）与最近锚点定位（预览闪示锚点）。
final class StringSearchTests: XCTestCase {

    // MARK: - uniqueLiteralRange

    func testUniqueLiteralRangeFindsSingleOccurrence() {
        let doc = "alpha beta gamma"
        let range = doc.uniqueLiteralRange(of: "beta")
        XCTAssertNotNil(range)
        XCTAssertEqual(range.map { String(doc[$0]) }, "beta")
    }

    func testUniqueLiteralRangeRejectsMultipleOccurrences() {
        // 多处相同文本无法确定目标——必须返回 nil 而不是猜第一个
        let doc = "same middle same"
        XCTAssertNil(doc.uniqueLiteralRange(of: "same"))
    }

    func testUniqueLiteralRangeRejectsMissingAndEmpty() {
        let doc = "hello world"
        XCTAssertNil(doc.uniqueLiteralRange(of: "absent"))
        XCTAssertNil(doc.uniqueLiteralRange(of: ""))
    }

    // MARK: - literalRange(of:nearestTo:)

    func testNearestMatchPrefersOccurrenceClosestToAnchor() {
        // 两处相同文本：锚点靠近第二处时必须命中第二处（闪错段落回归防护）
        let doc = "target filler filler filler target"
        let anchor = doc.index(doc.endIndex, offsetBy: -3)
        let range = doc.literalRange(of: "target", nearestTo: anchor)
        XCTAssertEqual(range.map { String(doc[$0]) }, "target")
        XCTAssertEqual(range.map { doc.distance(from: doc.startIndex, to: $0.lowerBound) }, 28)
    }

    func testNearestMatchFallsBackToFirstWhenAnchorAtStart() {
        let doc = "target filler target"
        let range = doc.literalRange(of: "target", nearestTo: doc.startIndex)
        XCTAssertEqual(range.map { doc.distance(from: doc.startIndex, to: $0.lowerBound) }, 0)
    }

    func testNearestMatchReturnsNilWhenAbsent() {
        let doc = "nothing here"
        XCTAssertNil(doc.literalRange(of: "target", nearestTo: doc.startIndex))
        XCTAssertNil(doc.literalRange(of: "", nearestTo: doc.startIndex))
    }
}
