import WebKit
import XCTest
@testable import MEditor

/// PreviewFindController 的可测逻辑：展示/关闭状态、命令分发、查询重置。
/// JS 查找本身（匹配计数/大小写）在 WebView 里执行，不在此处覆盖；
/// 这里只保证 Swift 侧状态装配正确。
@MainActor
final class PreviewFindControllerTests: XCTestCase {

    private var controller: PreviewFindController!

    override func setUp() {
        super.setUp()
        controller = PreviewFindController()
    }

    override func tearDown() {
        controller = nil
        super.tearDown()
    }

    // MARK: - 初始状态

    func testInitialState() {
        XCTAssertEqual(controller.activeMode, .empty)
        XCTAssertFalse(controller.isPresented)
        XCTAssertEqual(controller.query, "")
        XCTAssertTrue(controller.hasMatch)
        XCTAssertEqual(controller.focusToken, 0)
        XCTAssertEqual(controller.matchCount, 0)
        XCTAssertEqual(controller.currentMatchIndex, 0)
    }

    // MARK: - show / close 门槛

    func testShow_withoutWebView_staysHidden() {
        controller.activeMode = .markdown
        controller.show()
        XCTAssertFalse(controller.isPresented, "没有注册 WebView 时不应弹出查找栏")
        XCTAssertEqual(controller.focusToken, 0)
    }

    func testShow_nilWebView_staysHidden() {
        controller.register(webView: nil, for: .markdown)
        controller.activeMode = .markdown
        controller.show()
        XCTAssertFalse(controller.isPresented)
    }

    func testShow_withWebView_presentsAndBumpsFocusToken() {
        controller.register(webView: WKWebView(), for: .markdown)
        controller.activeMode = .markdown

        controller.show()
        XCTAssertTrue(controller.isPresented)
        XCTAssertEqual(controller.focusToken, 1)

        controller.show()
        XCTAssertEqual(controller.focusToken, 2, "重复 show 应继续推进焦点令牌")
    }

    func testShow_emptyQuery_resetsMatchState() {
        controller.register(webView: WKWebView(), for: .markdown)
        controller.activeMode = .markdown
        controller.hasMatch = false
        controller.matchCount = 7
        controller.currentMatchIndex = 3

        controller.show()
        XCTAssertTrue(controller.hasMatch)
        XCTAssertEqual(controller.matchCount, 0)
        XCTAssertEqual(controller.currentMatchIndex, 0)
    }

    func testShow_nonEmptyQuery_keepsMatchState() {
        // 已有查询时重新聚焦不应清空上次的匹配计数
        controller.register(webView: WKWebView(), for: .markdown)
        controller.activeMode = .markdown
        controller.query = "abc"
        controller.matchCount = 5
        controller.currentMatchIndex = 2

        controller.show()
        XCTAssertEqual(controller.matchCount, 5)
        XCTAssertEqual(controller.currentMatchIndex, 2)
    }

    func testClose_resetsEverything() {
        controller.register(webView: WKWebView(), for: .markdown)
        controller.activeMode = .markdown
        controller.show()
        controller.hasMatch = false
        controller.matchCount = 3
        controller.currentMatchIndex = 1

        controller.close()
        XCTAssertFalse(controller.isPresented)
        XCTAssertTrue(controller.hasMatch)
        XCTAssertEqual(controller.matchCount, 0)
        XCTAssertEqual(controller.currentMatchIndex, 0)
    }

    // MARK: - updateQuery

    func testUpdateQuery_emptyText_resetsMatchState() {
        controller.register(webView: WKWebView(), for: .markdown)
        controller.activeMode = .markdown
        controller.show()
        controller.query = "x"
        controller.hasMatch = false
        controller.matchCount = 2

        controller.updateQuery("")
        XCTAssertEqual(controller.query, "")
        XCTAssertTrue(controller.hasMatch)
        XCTAssertEqual(controller.matchCount, 0)
        XCTAssertEqual(controller.currentMatchIndex, 0)
    }

    func testUpdateQuery_nonEmpty_updatesQuery() {
        controller.register(webView: WKWebView(), for: .markdown)
        controller.activeMode = .markdown
        controller.show()
        controller.updateQuery("hello")
        XCTAssertEqual(controller.query, "hello")
        // 匹配计数由 150ms 防抖后的 JS 回填，这里只断言查询已落
    }

    // MARK: - handleCommand

    func testHandleCommand_unknownTag_returnsFalse() {
        XCTAssertFalse(controller.handleCommand(tag: 99))
        XCTAssertFalse(controller.handleCommand(tag: 0))
    }

    func testHandleCommand_show_withoutWebView_returnsFalse() {
        controller.activeMode = .markdown
        XCTAssertFalse(controller.handleCommand(tag: 1))
    }

    func testHandleCommand_show_withWebView_presents() {
        controller.register(webView: WKWebView(), for: .markdown)
        controller.activeMode = .markdown
        XCTAssertTrue(controller.handleCommand(tag: 1))
        XCTAssertTrue(controller.isPresented)
    }

    func testHandleCommand_findNext_emptyQuery_showsBar() {
        // 查找栏已展示 + 查询为空时，Cmd-G 应聚焦查找栏而不是触发搜索
        controller.register(webView: WKWebView(), for: .markdown)
        controller.activeMode = .markdown
        controller.show()
        let tokenBefore = controller.focusToken

        XCTAssertTrue(controller.handleCommand(tag: 2))
        XCTAssertEqual(controller.focusToken, tokenBefore + 1, "空查询的 Cmd-G 应等价于重新聚焦")
    }

    func testHandleCommand_findNext_notPresentedAndNoFocus_returnsFalse() {
        // 查找栏未展示且焦点不在 WebView（测试进程无 keyWindow）→ 不接管 Cmd-G
        controller.register(webView: WKWebView(), for: .markdown)
        controller.activeMode = .markdown
        XCTAssertFalse(controller.handleCommand(tag: 2))
        XCTAssertFalse(controller.handleCommand(tag: 3))
    }

    // MARK: - 双模式注册

    func testRegister_perMode_activeWebViewFollowsMode() {
        controller.register(webView: WKWebView(), for: .markdown)
        controller.activeMode = .html     // html 模式未注册 WebView
        controller.show()
        XCTAssertFalse(controller.isPresented, "activeMode 决定取哪个 WebView")

        controller.register(webView: WKWebView(), for: .html)
        controller.show()
        XCTAssertTrue(controller.isPresented)
    }
}
