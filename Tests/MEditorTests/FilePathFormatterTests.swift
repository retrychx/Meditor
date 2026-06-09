import XCTest
@testable import MEditor

final class FilePathFormatterTests: XCTestCase {
    func test_relativePath_returnsDescendantPathWithinRoot() {
        let rootURL = URL(fileURLWithPath: "/tmp/project")
        let fileURL = rootURL.appendingPathComponent("docs/spec.md")

        XCTAssertEqual(
            FilePathFormatter.relativePath(for: fileURL, rootURL: rootURL),
            "docs/spec.md"
        )
    }

    func test_relativePath_fallsBackToAbsolutePathOutsideRoot() {
        let rootURL = URL(fileURLWithPath: "/tmp/project")
        let fileURL = URL(fileURLWithPath: "/tmp/other/spec.md")

        XCTAssertEqual(
            FilePathFormatter.relativePath(for: fileURL, rootURL: rootURL),
            "/tmp/other/spec.md"
        )
    }
}
