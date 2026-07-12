import XCTest
@testable import MEditor

/// Verifies the URL construction / decoding logic used to route arbitrary
/// local file paths through the `meditor-asset://` scheme, bypassing
/// WKWebView's `allowingReadAccessTo` single-directory restriction.
final class MeditorAssetSchemeHandlerTests: XCTestCase {

    func test_baseURLString_encodesDirectoryPath_withTrailingSlash() {
        let dir = URL(fileURLWithPath: "/Users/test/My Docs")
        let base = MeditorAssetSchemeHandler.baseURLString(forDirectory: dir)

        XCTAssertTrue(base.hasPrefix("meditor-asset://local/"))
        XCTAssertTrue(base.hasSuffix("/"), "base href must end with '/' so relative paths resolve as siblings, not replace the last segment")
        XCTAssertTrue(base.contains("My%20Docs"), "spaces must be percent-encoded")
    }

    func test_baseURLPlusRelativePath_roundTripsToOriginalAbsolutePath() throws {
        let dir = URL(fileURLWithPath: "/Users/test/notes/assets")
        let base = MeditorAssetSchemeHandler.baseURLString(forDirectory: dir)

        // Simulate what the browser does when resolving <img src="pic.png">
        // against <base href="meditor-asset://local/Users/test/notes/assets/">.
        guard let baseURL = URL(string: base),
              let resolved = URL(string: "pic.png", relativeTo: baseURL) else {
            return XCTFail("failed to construct URL")
        }

        // Mirrors MeditorAssetSchemeHandler.decodeFilePath: percent-decode,
        // then standardize (folds the double-slash introduced by the "local" host).
        let decodedPath = try XCTUnwrap(resolved.path.removingPercentEncoding)
        let standardized = (decodedPath as NSString).standardizingPath
        XCTAssertEqual(standardized, "/Users/test/notes/assets/pic.png")
    }

    func test_baseURLPlusParentRelativePath_resolvesOutsideOriginalDirectory() throws {
        let dir = URL(fileURLWithPath: "/Users/test/notes/sub")
        let base = MeditorAssetSchemeHandler.baseURLString(forDirectory: dir)

        guard let baseURL = URL(string: base),
              let resolved = URL(string: "../assets/pic.png", relativeTo: baseURL) else {
            return XCTFail("failed to construct URL")
        }

        // Note: `resolved.path` already correctly resolves ".." segments per
        // RFC 3986 — do NOT call `.standardized` here, which mishandles the
        // custom scheme's host component and yields a wrong path.
        let decodedPath = try XCTUnwrap(resolved.path.removingPercentEncoding)
        let standardized = (decodedPath as NSString).standardizingPath
        XCTAssertEqual(standardized, "/Users/test/notes/assets/pic.png",
                       "relative '../' references must escape the base directory correctly, matching how markdown authors reference sibling asset folders")
    }
}
