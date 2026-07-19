import XCTest
@testable import MEditor

final class PresentationExporterTests: XCTestCase {

    /// 源码树内的 Presentation 资源目录。
    /// 测试进程无法经 Bundle.main 定位 app bundle 资源，因此直接注入路径。
    private var presentationRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // MEditorTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // 仓库根
            .appendingPathComponent("Sources/MEditor/Resources/Presentation", isDirectory: true)
    }

    private func makeHTML(
        slides: [String] = ["# Hello", "world ![img](images/a.png)"],
        theme: PreviewTheme = .nord,
        baseHref: String = "file:///tmp/docs/"
    ) -> String? {
        PresentationExporter.makeHTML(
            slides: slides,
            theme: theme,
            baseHref: baseHref,
            presentationRoot: presentationRoot
        )
    }

    func test_makeHTML_inlinesAllResources() {
        let html = makeHTML()
        XCTAssertNotNil(html)
        // 外链引用应全部被内联替换
        XCTAssertFalse(html!.contains("<script src="))
        XCTAssertFalse(html!.contains("<link rel=\"stylesheet\""))
        // 内联后的 marked / highlight / slides.js 特征标识
        XCTAssertTrue(html!.contains("marked"))
        XCTAssertTrue(html!.contains("hljs"))
        XCTAssertTrue(html!.contains("window.MEditorSlides"))
    }

    func test_makeHTML_inlinesSlidesJSON() {
        let html = makeHTML(slides: ["# 第一页", "第二页 内容"])
        XCTAssertNotNil(html)
        XCTAssertTrue(html!.contains("# 第一页"))
        XCTAssertTrue(html!.contains("第二页 内容"))
    }

    func test_makeHTML_themeClassBaseHrefAndBootCall() {
        let html = makeHTML()
        XCTAssertNotNil(html)
        XCTAssertTrue(html!.contains("class=\"theme-nord\""))   // <html> 初始主题 class
        XCTAssertTrue(html!.contains("\"theme\":\"nord\""))     // boot payload 主题
        // JSONSerialization 会把 / 转义为 \/（JS 解析时还原，与放映窗口注入行为一致）
        XCTAssertTrue(html!.contains("\"baseHref\":\"file:\\/\\/\\/tmp\\/docs\\/\""))
        XCTAssertTrue(html!.contains("MEditorSlides.boot("))    // 加载后自动 boot
    }

    func test_makeHTML_missingResources_returnsNil() {
        let missing = URL(fileURLWithPath: "/tmp/meditor-nonexistent-\(UUID().uuidString)")
        let html = PresentationExporter.makeHTML(
            slides: ["# A"],
            theme: .github,
            baseHref: "",
            presentationRoot: missing
        )
        XCTAssertNil(html)
    }
}
