import XCTest
@testable import MEditor

/// AppState.lineNumber：字符位置 → 1-based 行号（改哪亮哪的行区间计算）。
final class PreviewChangeLineTests: XCTestCase {

    func test_lineNumber_firstLine() {
        let s = "abc\ndef"
        XCTAssertEqual(AppState.lineNumber(of: s.startIndex, in: s), 1)
    }

    func test_lineNumber_afterNewlines() {
        let s = "line1\nline2\nline3"
        let third = s.range(of: "line3")!.lowerBound
        XCTAssertEqual(AppState.lineNumber(of: third, in: s), 3)
    }

    func test_lineNumber_atEnd() {
        let s = "a\nb"
        XCTAssertEqual(AppState.lineNumber(of: s.endIndex, in: s), 2)
    }

    func test_changedPulseJS_containsRangeAndCleanup() {
        let js = AppState.changedPulseJS(start: 3, end: 7)
        XCTAssertTrue(js.contains("l >= 3 && l <= 7"))
        XCTAssertTrue(js.contains("meditor-changed"))
        XCTAssertTrue(js.contains("setTimeout"))   // 自动清除
    }
}
