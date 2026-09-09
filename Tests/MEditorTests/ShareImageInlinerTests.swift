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
        // （PNG 魔数开头 + 填充——内联前有真实图片格式嗅探，纯填充数据会被拒）
        let chunk = pngData + Data(repeating: 0xCD, count: 1_400_000 - pngData.count)
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

    // MARK: - 安全：路径 confine + 魔数嗅探

    /// 相对路径解析后必须仍在 baseDirectory 内——否则 `../..` 能把任意文件
    /// 内联进发布到公网的 HTML。
    func testRelativePathEscapingBaseDirectoryNotInlined() {
        // 在 baseDirectory 的父目录放一张"图片"，用 ../ 引用它
        let outside = tempDir.deletingLastPathComponent().appendingPathComponent("outside-\(UUID().uuidString).png")
        try! pngData.write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }

        let html = img("../\(outside.lastPathComponent)")
        XCTAssertEqual(ShareImageInliner.inlineImages(in: html, baseDirectory: tempDir), html)
    }

    /// 扩展名伪装成图片的文本文件不内联（魔数嗅探）。
    func testNonImageContentNotInlined() {
        write("secret.png", Data("-----BEGIN OPENSSH PRIVATE KEY-----".utf8))
        let html = img("secret.png")
        XCTAssertEqual(ShareImageInliner.inlineImages(in: html, baseDirectory: tempDir), html)
    }

    func testResolveFileURLConfinesRelativePaths() {
        let inside = ShareImageInliner.resolveFileURL(src: "assets/pic.png", baseDirectory: tempDir)
        XCTAssertNotNil(inside)
        XCTAssertTrue(inside!.path.hasPrefix(tempDir.standardizedFileURL.path + "/"))

        XCTAssertNil(ShareImageInliner.resolveFileURL(src: "../pic.png", baseDirectory: tempDir))
        XCTAssertNil(ShareImageInliner.resolveFileURL(src: "../../etc/passwd", baseDirectory: tempDir))
        // 百分号编码的 .. 同样挡住
        XCTAssertNil(ShareImageInliner.resolveFileURL(src: "%2E%2E/pic.png", baseDirectory: tempDir))
    }

    func testImageDataSniffing() {
        XCTAssertTrue(ShareImageInliner.isSupportedImageData(pngData))
        XCTAssertTrue(ShareImageInliner.isSupportedImageData(Data([0xFF, 0xD8, 0xFF, 0xE0]))) // JPEG
        XCTAssertTrue(ShareImageInliner.isSupportedImageData(Data("GIF89a".utf8) + Data(repeating: 0, count: 10)))
        XCTAssertTrue(ShareImageInliner.isSupportedImageData(Data("RIFF".utf8) + Data(repeating: 0, count: 4) + Data("WEBP".utf8) + Data(repeating: 0, count: 4)))
        XCTAssertTrue(ShareImageInliner.isSupportedImageData(Data(svgString.utf8)))
        XCTAssertTrue(ShareImageInliner.isSupportedImageData(Data("<?xml version=\"1.0\"?>\n<svg xmlns=\"http://www.w3.org/2000/svg\"/>".utf8)))

        XCTAssertFalse(ShareImageInliner.isSupportedImageData(Data("plain text".utf8)))
        XCTAssertFalse(ShareImageInliner.isSupportedImageData(Data("#!/bin/sh\necho hi".utf8)))
        XCTAssertFalse(ShareImageInliner.isSupportedImageData(Data()))
    }
}
