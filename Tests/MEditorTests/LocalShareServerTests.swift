import XCTest
@testable import MEditor

@MainActor
final class LocalShareServerTests: XCTestCase {

    func test_inlineJavaScriptStringLiteral_escapesClosingScriptTag() {
        let encoded = LocalShareServer.inlineJavaScriptStringLiteral(#"</script><script>alert(1)</script>"#)

        XCTAssertNotNil(encoded)
        XCTAssertFalse(encoded!.contains("</script>"))
        XCTAssertTrue(encoded!.contains(#"<\/script>"#))
    }

    func test_extractMarkdownReferences_findsImageAndLinkTargets() {
        let refs = LocalShareServer.extractMarkdownReferences(from: """
        ![Diagram](./assets/diagram.png)
        [Spec](./docs/spec.pdf "Spec")
        """)

        XCTAssertEqual(refs, ["./assets/diagram.png", #"./docs/spec.pdf "Spec""#])
    }

    func test_extractHTMLReferences_findsSrcAndHrefTargets() {
        let refs = LocalShareServer.extractHTMLReferences(from: #"""
        <link href="./styles/site.css">
        <img src="./images/cover.png">
        """#)

        XCTAssertEqual(refs, ["./styles/site.css", "./images/cover.png"])
    }

    func test_allowedFiles_onlyExposeReferencedAssets() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MEditorShareTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let assetsDir = tempDir.appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assetsDir, withIntermediateDirectories: true)

        let markdownURL = tempDir.appendingPathComponent("readme.md")
        let exposedAsset = assetsDir.appendingPathComponent("cover.png")
        let hiddenAsset = assetsDir.appendingPathComponent("secret.json")

        try "![Cover](./assets/cover.png)".write(to: markdownURL, atomically: true, encoding: .utf8)
        try Data().write(to: exposedAsset)
        try "{}".write(to: hiddenAsset, atomically: true, encoding: .utf8)

        let server = LocalShareServer()
        server.rootURL = tempDir
        server.allowedFiles = [markdownURL]

        XCTAssertTrue(server.isAllowedAsset(exposedAsset))
        XCTAssertFalse(server.isAllowedAsset(hiddenAsset))
    }
}
