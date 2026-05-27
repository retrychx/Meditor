import XCTest
@testable import MEditor

final class PreviewExporterTests: XCTestCase {

    var exporter: PreviewExporter!

    override func setUp() {
        super.setUp()
        exporter = PreviewExporter()
    }

    override func tearDown() {
        exporter = nil
        super.tearDown()
    }

    // MARK: - No WebView

    func test_export_failsWithNoWebView() {
        let expectation = expectation(description: "export completes")

        exporter.export(format: .html, suggestedName: "test") { result in
            switch result {
            case .failure(let error):
                XCTAssertEqual(error.errorDescription, "Preview is not available.")
            case .success:
                XCTFail("Should have failed without webview")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func test_export_pdf_failsWithNoWebView() {
        let expectation = expectation(description: "pdf export completes")

        exporter.export(format: .pdf, suggestedName: "test") { result in
            switch result {
            case .failure(let error):
                XCTAssertEqual(error.errorDescription, "Preview is not available.")
            case .success:
                XCTFail("Should have failed without webview")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func test_export_image_failsWithNoWebView() {
        let expectation = expectation(description: "image export completes")

        exporter.export(format: .image, suggestedName: "test") { result in
            switch result {
            case .failure(let error):
                XCTAssertEqual(error.errorDescription, "Preview is not available.")
            case .success:
                XCTFail("Should have failed without webview")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Export Availability

    func test_isExportAvailable_falseByDefault() {
        XCTAssertFalse(exporter.isExportAvailable)
    }

    // MARK: - Error Descriptions

    func test_exportError_descriptions() {
        let noWebView = PreviewExporter.ExportError.noWebView
        XCTAssertEqual(noWebView.errorDescription, "Preview is not available.")

        let jsFailed = PreviewExporter.ExportError.javaScriptFailed("timeout")
        XCTAssertEqual(jsFailed.errorDescription, "Export failed (JS): timeout")

        let pdfFailed = PreviewExporter.ExportError.pdfGenerationFailed("no data")
        XCTAssertEqual(pdfFailed.errorDescription, "PDF export failed: no data")

        let snapFailed = PreviewExporter.ExportError.snapshotFailed("render error")
        XCTAssertEqual(snapFailed.errorDescription, "Image export failed: render error")
    }
}
