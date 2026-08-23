import XCTest
@testable import MEditor

/// HTML 预览改由内存内容（tab.content）驱动：AI 写回/编辑后不落盘也要立即刷新。
@MainActor
final class PreviewManagerHTMLTests: XCTestCase {

    private func makeTab(content: String) -> EditorTab {
        EditorTab(url: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).html"),
                  content: content, language: .html)
    }

    func testHTMLSyncStoresInMemoryContent() {
        let pm = PreviewManager()
        pm.sync(from: makeTab(content: "<h1>a</h1>"))
        XCTAssertEqual(pm.mode, .html)
        XCTAssertEqual(pm.content, "<h1>a</h1>")
    }

    func testHTMLContentChangeSameURLBumpsReloadToken() {
        let pm = PreviewManager()
        let url = URL(fileURLWithPath: "/tmp/\(UUID().uuidString).html")
        pm.sync(from: EditorTab(url: url, content: "<h1>a</h1>", language: .html))
        let token = pm.previewReloadTokenSentinel
        pm.sync(from: EditorTab(url: url, content: "<h1>b</h1>", language: .html))
        XCTAssertGreaterThan(pm.previewReloadTokenSentinel, token)
    }

    func testHTMLSameContentDoesNotBumpReloadToken() {
        let pm = PreviewManager()
        let url = URL(fileURLWithPath: "/tmp/\(UUID().uuidString).html")
        pm.sync(from: EditorTab(url: url, content: "<h1>a</h1>", language: .html))
        let token = pm.previewReloadTokenSentinel
        pm.sync(from: EditorTab(url: url, content: "<h1>a</h1>", language: .html))
        XCTAssertEqual(pm.previewReloadTokenSentinel, token)
    }

    func testSwitchingToMarkdownClearsHTMLState() {
        let pm = PreviewManager()
        pm.sync(from: makeTab(content: "<h1>a</h1>"))
        pm.sync(from: EditorTab(url: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).md"),
                                content: "# hi", language: .markdown))
        XCTAssertEqual(pm.mode, .markdown)
        XCTAssertNil(pm.htmlFileURL)
        XCTAssertEqual(pm.content, "# hi")
    }
}

private extension PreviewManager {
    /// 测试可读包装（reloadToken 是内部状态，这里只是别名，语义不变）。
    var previewReloadTokenSentinel: Int { reloadToken }
}
