import XCTest
@testable import MEditor

/// UpdatePanelState 的纯状态测试：初始值、clearActions 语义、Phase 枚举完整性。
@MainActor
final class UpdatePanelStateTests: XCTestCase {

    func testInitialState() {
        let state = UpdatePanelState()
        XCTAssertEqual(state.phase, .checking)
        XCTAssertEqual(state.newVersion, "")
        XCTAssertEqual(state.currentVersion, "")
        XCTAssertNil(state.releaseNotesHTML)
        XCTAssertEqual(state.receivedBytes, 0)
        XCTAssertEqual(state.expectedBytes, 0)
        XCTAssertEqual(state.extractionProgress, 0)
        XCTAssertEqual(state.errorMessage, "")
        XCTAssertNil(state.primaryAction)
        XCTAssertNil(state.secondaryAction)
        XCTAssertNil(state.tertiaryAction)
        XCTAssertNil(state.cancelAction)
        XCTAssertNil(state.dismissAction)
    }

    func testClearActions_nilsAllFiveActions() {
        let state = UpdatePanelState()
        let noop = {}
        state.primaryAction = noop
        state.secondaryAction = noop
        state.tertiaryAction = noop
        state.cancelAction = noop
        state.dismissAction = noop

        state.clearActions()

        XCTAssertNil(state.primaryAction)
        XCTAssertNil(state.secondaryAction)
        XCTAssertNil(state.tertiaryAction)
        XCTAssertNil(state.cancelAction)
        XCTAssertNil(state.dismissAction)
    }

    func testClearActions_keepsDataFields() {
        // clearActions 只清回调，不动数据字段（面板重排时阶段数据要保留）
        let state = UpdatePanelState()
        state.phase = .found
        state.newVersion = "9.9"
        state.errorMessage = "boom"
        state.primaryAction = {}

        state.clearActions()

        XCTAssertEqual(state.phase, .found)
        XCTAssertEqual(state.newVersion, "9.9")
        XCTAssertEqual(state.errorMessage, "boom")
    }
}
