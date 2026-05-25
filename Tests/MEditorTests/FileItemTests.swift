import XCTest
@testable import MEditor

final class FileItemTests: XCTestCase {

    func test_name_usesLastPathComponent() {
        let url = URL(fileURLWithPath: "/Users/test/hello.md")
        let item = FileItem(url: url, isDirectory: false)
        XCTAssertEqual(item.name, "hello.md")
    }

    func test_fileExtension_lowercased() {
        let url = URL(fileURLWithPath: "/test/ReadMe.MD")
        let item = FileItem(url: url, isDirectory: false)
        XCTAssertEqual(item.fileExtension, "md")
    }

    func test_fileExtension_noExtension() {
        let url = URL(fileURLWithPath: "/test/README")
        let item = FileItem(url: url, isDirectory: false)
        XCTAssertEqual(item.fileExtension, "")
    }

    func test_isSupported_directory() {
        let url = URL(fileURLWithPath: "/test/subdir")
        let item = FileItem(url: url, isDirectory: true)
        XCTAssertTrue(item.isSupported)
    }

    func test_isSupported_markdown() {
        let url = URL(fileURLWithPath: "/test/doc.md")
        let item = FileItem(url: url, isDirectory: false)
        XCTAssertTrue(item.isSupported)
    }

    func test_isSupported_unsupportedExtension() {
        let url = URL(fileURLWithPath: "/test/script.js")
        let item = FileItem(url: url, isDirectory: false)
        XCTAssertFalse(item.isSupported)
    }

    func test_hashable_equality_byId() {
        let url1 = URL(fileURLWithPath: "/test/a.md")
        let url2 = URL(fileURLWithPath: "/test/b.md")
        let item1 = FileItem(url: url1, isDirectory: false)
        let item2 = FileItem(url: url1, isDirectory: false)  // same url but different id

        // Two items with same URL but different IDs should NOT be equal
        XCTAssertNotEqual(item1, item2)

        // Same instance should be equal
        XCTAssertEqual(item1, item1)
    }

    func test_hashable_consistency() {
        let url = URL(fileURLWithPath: "/test/doc.md")
        let item = FileItem(url: url, isDirectory: false)
        let set: Set<FileItem> = [item]
        XCTAssertTrue(set.contains(item))
    }

    func test_fileExtension_fromComplexPath() {
        let url = URL(fileURLWithPath: "/test/some.file.name.html")
        let item = FileItem(url: url, isDirectory: false)
        XCTAssertEqual(item.fileExtension, "html")
    }
}
