import XCTest
@testable import MEditor

/// ShareImageInliner：发布前把本地图片引用改写成 data URI。
final class ShareImageInlinerTests: XCTestCase {

    private var tempDir: URL!

    /// 1x1 透明 PNG（68 字节）。
    private let pngData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")!
    private let svgString = #"<svg xmlns="http://www.w3.org/2000/svg" width="1" height="1"/>"#

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("inliner-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func write(_ name: String, _ data: Data) -> URL {
        let url = tempDir.appendingPathComponent(name)
        try! data.write(to: url)
        return url
    }

    private func img(_ src: String) -> String {
        #"<p><img src="\#(src)" alt="x"></p>"#
    }

    /// 抽出改写后 HTML 里的 data URI 并解码校验。
    private func assertInlinedPNG(_ html: String, expected: Data, file: StaticString = #filePath, line: UInt = #line) {
        guard let range = html.range(of: #"src="data:image/png;base64,([^"]*)""#, options: .regularExpression) else {
            return XCTFail("未找到内联的 PNG data URI：\(html)", file: file, line: line)
        }
        let b64 = String(html[range].dropFirst("src=\"data:image/png;base64,".count).dropLast(1))
        XCTAssertEqual(Data(base64Encoded: b64), expected, file: file, line: line)
    }

    func testRelativePathInlined() {
        let file = write("pic.png", pngData)
        let html = ShareImageInliner.inlineImages(in: img("./pic.png"), baseDirectory: tempDir)
        assertInlinedPNG(html, expected: pngData)
        XCTAssertFalse(html.contains(file.path))
    }

    func testSubdirectoryAndSpaceInName() {
        try! FileManager.default.createDirectory(at: tempDir.appendingPathComponent("assets"), withIntermediateDirectories: true)
        let data = pngData
        try! data.write(to: tempDir.appendingPathComponent("assets/my pic.png"))
        let html = ShareImageInliner.inlineImages(in: img("assets/my%20pic.png"), baseDirectory: tempDir)
        assertInlinedPNG(html, expected: pngData)
    }

    func testMeditorAssetURLInlined() {
        let file = write("abs.png", pngData)
        let encoded = file.path.split(separator: "/").map { String($0) }.joined(separator: "/")
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!
        let src = "meditor-asset://local/\(encoded)"
        let html = ShareImageInliner.inlineImages(in: img(src), baseDirectory: tempDir)
        assertInlinedPNG(html, expected: pngData)
    }

    func testFileURLInlined() {
        let file = write("f.png", pngData)
        let html = ShareImageInliner.inlineImages(in: img(file.absoluteString), baseDirectory: tempDir)
        assertInlinedPNG(html, expected: pngData)
    }

    func testRemoteAndDataURIsUntouched() {
        let remote = img("https://example.com/a.png") + img("http://example.com/b.png")
        let html = ShareImageInliner.inlineImages(in: remote, baseDirectory: tempDir)
        XCTAssertEqual(html, remote)

        let inline = img("data:image/png;base64,AAAA")
        XCTAssertEqual(ShareImageInliner.inlineImages(in: inline, baseDirectory: tempDir), inline)
    }

    func testMissingFileUntouched() {
        let html = img("./nope.png")
        XCTAssertEqual(ShareImageInliner.inlineImages(in: html, baseDirectory: tempDir), html)
    }

    func testSVGMimeType() {
        write("icon.svg", Data(svgString.utf8))
        let html = ShareImageInliner.inlineImages(in: img("icon.svg"), baseDirectory: tempDir)
        XCTAssertTrue(html.contains("src=\"data:image/svg+xml;base64,"), html)
    }

    func testOversizedImageSkipped() {
        let big = Data(repeating: 0xAB, count: ShareImageInliner.maxImageBytes + 1)
        write("big.png", big)
        let html = img("./big.png")
        XCTAssertEqual(ShareImageInliner.inlineImages(in: html, baseDirectory: tempDir), html)
    }

    func testTotalBudgetStopsLaterImages() {
        // 三张 1.4MB 的图（单图未超上限）：前两张内联（2.8MB），第三张超总预算被跳过
        let chunk = Data(repeating: 0xCD, count: 1_400_000)
        write("a.png", chunk)
        write("b.png", chunk)
        write("c.png", chunk)
        let html = img("./a.png") + img("./b.png") + img("./c.png")
        let out = ShareImageInliner.inlineImages(in: html, baseDirectory: tempDir)
        XCTAssertEqual(out.components(separatedBy: "data:image/png;base64,").count - 1, 2)
        XCTAssertTrue(out.contains("./c.png"))
        XCTAssertFalse(out.contains("./a.png"))
        XCTAssertFalse(out.contains("./b.png"))
    }

    func testNoImagesUnchanged() {
        let html = "<p>纯文本</p>"
        XCTAssertEqual(ShareImageInliner.inlineImages(in: html, baseDirectory: tempDir), html)
    }
}
