import XCTest
@testable import MEditor

final class FileTypeConfigurationTests: XCTestCase {

    func test_supportedExtensions_containsMarkdown() {
        let exts = FileTypeConfiguration.shared.supportedExtensions
        XCTAssertTrue(exts.contains("md"))
        XCTAssertTrue(exts.contains("markdown"))
    }

    func test_supportedExtensions_containsHTML() {
        let exts = FileTypeConfiguration.shared.supportedExtensions
        XCTAssertTrue(exts.contains("html"))
        XCTAssertTrue(exts.contains("htm"))
    }

    func test_supportedExtensions_doesNotContainUnsupported() {
        let exts = FileTypeConfiguration.shared.supportedExtensions
        XCTAssertFalse(exts.contains("js"))
        XCTAssertFalse(exts.contains("json"))
        XCTAssertFalse(exts.contains("css"))
    }

    func test_editorLanguage_forMarkdown() {
        XCTAssertEqual(
            FileTypeConfiguration.shared.editorLanguage(for: "md"),
            .markdown
        )
        XCTAssertEqual(
            FileTypeConfiguration.shared.editorLanguage(for: "markdown"),
            .markdown
        )
    }

    func test_editorLanguage_forHTML() {
        XCTAssertEqual(
            FileTypeConfiguration.shared.editorLanguage(for: "html"),
            .html
        )
        XCTAssertEqual(
            FileTypeConfiguration.shared.editorLanguage(for: "htm"),
            .html
        )
    }

    func test_editorLanguage_forUnknownReturnsNil() {
        XCTAssertNil(FileTypeConfiguration.shared.editorLanguage(for: "js"))
        XCTAssertNil(FileTypeConfiguration.shared.editorLanguage(for: "txt"))
    }

    func test_descriptor_forUnknownReturnsDefault() {
        let desc = FileTypeConfiguration.shared.descriptor(for: "txt")
        XCTAssertEqual(desc.icon, "doc")
        XCTAssertNil(desc.editorLanguage)
    }

    func test_icon_forMarkdown() {
        XCTAssertEqual(FileTypeConfiguration.shared.icon(for: "md"), "doc.text")
    }

    func test_icon_forHTML() {
        XCTAssertEqual(FileTypeConfiguration.shared.icon(for: "html"), "globe")
    }

    func test_supportedPreviewExtensions() {
        let previewExts = FileTypeConfiguration.shared.supportedPreviewExtensions
        XCTAssertTrue(previewExts.contains("md"))
        XCTAssertTrue(previewExts.contains("html"))
        XCTAssertFalse(previewExts.contains("txt"))
    }

    func test_caseInsensitivity() {
        XCTAssertEqual(
            FileTypeConfiguration.shared.editorLanguage(for: "MD"),
            .markdown
        )
        XCTAssertEqual(
            FileTypeConfiguration.shared.editorLanguage(for: "HTML"),
            .html
        )
    }
}
