import XCTest
@testable import MEditor

final class SlideSplitterTests: XCTestCase {

    func test_singlePage_noSeparator() {
        let md = "# Title\n\nSome text.\n"
        XCTAssertEqual(SlideSplitter.split(md), [md.replacingOccurrences(of: "\r\n", with: "\n")])
    }

    func test_basicSplit() {
        let md = "# A\n\n---\n\n# B\n"
        XCTAssertEqual(SlideSplitter.split(md), ["# A\n", "\n# B\n"])
    }

    func test_separatorWithWhitespace() {
        let md = "# A\n  ---  \n# B"
        XCTAssertEqual(SlideSplitter.split(md).count, 2)
    }

    func test_crlfSeparator() {
        let md = "# A\r\n---\r\n# B"
        XCTAssertEqual(SlideSplitter.split(md).count, 2)
    }

    func test_frontMatter_notAPageBreak() {
        let md = "---\ntitle: Hello\ndate: 2026-01-01\n---\n# Slide 1\n---\n# Slide 2"
        let slides = SlideSplitter.split(md)
        XCTAssertEqual(slides.count, 2)
        XCTAssertFalse(slides[0].contains("title:"))
        XCTAssertTrue(slides[0].contains("# Slide 1"))
        XCTAssertTrue(slides[1].contains("# Slide 2"))
    }

    func test_frontMatter_only() {
        let md = "---\ntitle: Only\n---\nBody"
        XCTAssertEqual(SlideSplitter.split(md), ["Body"])
    }

    func test_separatorInsideCodeFence_ignored() {
        let md = "# A\n\n```\n---\n```\n\n---\n\n# B"
        let slides = SlideSplitter.split(md)
        XCTAssertEqual(slides.count, 2)
        XCTAssertTrue(slides[0].contains("```\n---\n```"))
    }

    func test_separatorInsideTildeFence_ignored() {
        let md = "~~~\n---\n~~~\n---\nB"
        XCTAssertEqual(SlideSplitter.split(md).count, 2)
    }

    func test_indentedFence() {
        let md = "  ```swift\n  ---\n  ```\n---\nB"
        XCTAssertEqual(SlideSplitter.split(md).count, 2)
    }

    func test_emptyDocument_singlePage() {
        XCTAssertEqual(SlideSplitter.split(""), [""])
    }

    func test_consecutiveSeparators_noEmptyPages() {
        let md = "# A\n---\n---\n# B"
        XCTAssertEqual(SlideSplitter.split(md).count, 2)
    }
}
