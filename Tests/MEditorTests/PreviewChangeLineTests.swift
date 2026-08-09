import XCTest
@testable import MEditor

/// AppState.lineNumber：字符位置 → 0-based 行号（与渲染层 data-source-line 对齐，
/// render.js collectHeadingLines push 的是 split('\n') 下标，编辑器 scrollToLine 同为 0-based）。
final class PreviewChangeLineTests: XCTestCase {

    func test_lineNumber_firstLine() {
        let s = "abc\ndef"
        XCTAssertEqual(AppState.lineNumber(of: s.startIndex, in: s), 0)
    }

    func test_lineNumber_afterNewlines() {
        let s = "line1\nline2\nline3"
        let third = s.range(of: "line3")!.lowerBound
        XCTAssertEqual(AppState.lineNumber(of: third, in: s), 2)
    }

    func test_lineNumber_atEnd() {
        let s = "a\nb"
        XCTAssertEqual(AppState.lineNumber(of: s.endIndex, in: s), 1)
    }

    func test_changedPulseJS_containsRangeAndCleanup() {
        let js = AppState.changedPulseJS(start: 3, end: 7)
        XCTAssertTrue(js.contains("l >= 3 && l <= 7"))
        XCTAssertTrue(js.contains("meditor-changed"))
        XCTAssertTrue(js.contains("setTimeout"))   // 自动清除
    }

    func test_changedPulseJS_hasNearestHeadingFallback() {
        // 非标题改动命中不到 [data-source-line] 时，回退到 start 之前最近的标题锚点
        let js = AppState.changedPulseJS(start: 5, end: 6)
        XCTAssertTrue(js.contains("fallback"))
        XCTAssertTrue(js.contains("l <= 5"))
        XCTAssertTrue(js.contains("hits.length === 0 && fallback"))
    }
}
