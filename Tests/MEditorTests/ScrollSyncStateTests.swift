import XCTest
@testable import MEditor

final class ScrollSyncStateTests: XCTestCase {

    func test_editorDrivenScroll_suppressesNextPreviewEchoOnly() {
        var state = ScrollSyncState()

        XCTAssertTrue(state.shouldPropagateEditorScroll())
        XCTAssertFalse(state.shouldPropagatePreviewScroll())
        XCTAssertTrue(state.shouldPropagatePreviewScroll())
    }

    func test_previewDrivenScroll_suppressesNextEditorEchoOnly() {
        var state = ScrollSyncState()

        XCTAssertTrue(state.shouldPropagatePreviewScroll())
        XCTAssertFalse(state.shouldPropagateEditorScroll())
        XCTAssertTrue(state.shouldPropagateEditorScroll())
    }

    func test_tocNavigation_suppressesOneEchoOnBothSides() {
        var state = ScrollSyncState()
        state.registerTOCNavigation()

        XCTAssertFalse(state.shouldPropagatePreviewScroll())
        XCTAssertFalse(state.shouldPropagateEditorScroll())
        XCTAssertTrue(state.shouldPropagateEditorScroll())
        XCTAssertFalse(state.shouldPropagatePreviewScroll())
    }
}
