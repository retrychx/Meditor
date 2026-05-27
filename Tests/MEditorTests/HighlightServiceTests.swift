import XCTest
@testable import MEditor

final class HighlightServiceTests: XCTestCase {

    func test_engine_returnsMarkdownEngine() {
        let engine = HighlightService.shared.engine(for: .markdown)
        XCTAssertNotNil(engine)
        XCTAssertTrue(engine is MarkdownHighlightEngine)
    }

    func test_engine_returnsHTMLEngine() {
        let engine = HighlightService.shared.engine(for: .html)
        XCTAssertNotNil(engine)
        XCTAssertTrue(engine is HTMLHighlightEngine)
    }

    func test_register_overridesExistingEngine() {
        let custom = MarkdownHighlightEngine()
        HighlightService.shared.register(.html, engine: custom)

        let engine = HighlightService.shared.engine(for: .html)
        XCTAssertTrue(engine is MarkdownHighlightEngine)

        // Restore original
        HighlightService.shared.register(.html, engine: HTMLHighlightEngine())
    }
}
