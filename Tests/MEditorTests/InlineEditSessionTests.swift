import XCTest
@testable import MEditor

// MARK: - InlineEditSessionTests
//
// 内联编辑写回的 tab 锁定测试：AI 运行期间用户切换 tab 时，sourceTabIfCurrent
// 必须返回 nil（provider 不进 rebase、onFinalize 中止写回并提示），绝不把
// AI 结果合并进别的文档（对齐 SlashAICommandExecutor 的 sourceTabID 模式）。

@MainActor
final class InlineEditSessionTests: XCTestCase {

    private var state: AppState!
    private var fileService: MockFileService!

    override func setUp() {
        super.setUp()
        fileService = MockFileService()
        state = AppState(fileService: fileService, fileWatcher: MockFileWatcher())
    }

    override func tearDown() {
        state = nil
        fileService = nil
        super.tearDown()
    }

    /// 打开一个内存假文件并返回新建/选中的 tab（小文件同步选中，见 TabManager.openFile）
    private func openTab(_ name: String, content: String) -> EditorTab {
        let url = URL(fileURLWithPath: "/tmp/\(name)")
        fileService.setFile(url, content: content)
        state.openFile(FileItem(url: url, isDirectory: false))
        guard let tab = state.selectedTab else {
            fatalError("openFile 后应有选中 tab")
        }
        return tab
    }

    func testSourceTabIfCurrent_sameTab_returnsTab() {
        let tabA = openTab("a.md", content: "A")
        XCTAssertEqual(InlineEditSession.sourceTabIfCurrent(state, sourceTabID: tabA.id)?.id, tabA.id)
    }

    func testSourceTabIfCurrent_tabSwitched_returnsNil() {
        let tabA = openTab("a.md", content: "A")
        let tabB = openTab("b.md", content: "B")   // AI 运行期间用户切到 tab B
        XCTAssertNil(InlineEditSession.sourceTabIfCurrent(state, sourceTabID: tabA.id),
                     "当前 tab 不是发起 tab 时必须拒绝写回")
        XCTAssertEqual(InlineEditSession.sourceTabIfCurrent(state, sourceTabID: tabB.id)?.id, tabB.id)
    }

    func testSourceTabIfCurrent_noSelectedTab_returnsNil() {
        XCTAssertNil(state.selectedTab)
        XCTAssertNil(InlineEditSession.sourceTabIfCurrent(state, sourceTabID: nil),
                     "无选中 tab 时不得写回")
    }
}
