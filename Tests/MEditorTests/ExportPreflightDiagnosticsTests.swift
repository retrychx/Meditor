import XCTest
@testable import MEditor

/// 导出前检查（功能7）依赖的诊断能力补充：
/// 空标题、未闭合代码块的检出，以及严重度分级。
final class ExportPreflightDiagnosticsTests: XCTestCase {

    private let fileURL = URL(fileURLWithPath: "/tmp/doc.md")
    private let noFile: (URL) -> Bool = { _ in false }

    private func run(_ content: String) -> [DocumentIssue] {
        DocumentDiagnostics.issues(in: content, fileURL: fileURL, fileExists: noFile)
    }

    // MARK: - 空标题

    func test_emptyHeading_flagged() {
        let issues = run("# Title\n\n## \n\nbody\n")
        XCTAssertEqual(issues.map(\.kind), [.emptyHeading])
        XCTAssertEqual(issues.first?.line, 2)
    }

    func test_emptyHeading_notCountedAsDuplicate() {
        // 两个空标题不应再报 duplicateHeading，各报一次 emptyHeading
        let issues = run("## \n\n## \n")
        XCTAssertEqual(issues.map(\.kind), [.emptyHeading, .emptyHeading])
    }

    // MARK: - 未闭合代码块

    func test_unclosedCodeBlock_flaggedAtOpeningLine() {
        let issues = run("text\n\n```swift\nlet a = 1\n")
        XCTAssertEqual(issues.map(\.kind), [.unclosedCodeBlock])
        XCTAssertEqual(issues.first?.line, 2)
    }

    func test_closedCodeBlock_notFlagged() {
        XCTAssertTrue(run("```\ncode\n```\n").isEmpty)
    }

    func test_unclosedTildeBlock_flagged() {
        let issues = run("~~~\ncode\n")
        XCTAssertEqual(issues.map(\.kind), [.unclosedCodeBlock])
    }

    func test_mismatchedFenceMarker_stillUnclosed() {
        // 开栏 ``` 而 ~~~ 不算关栏
        let issues = run("```\ncode\n~~~\n")
        XCTAssertEqual(issues.map(\.kind), [.unclosedCodeBlock])
    }

    // MARK: - 严重度分级

    func test_severity_missingImageIsError() {
        let issue = DocumentIssue(kind: .missingImage("a.png"), fileURL: fileURL, line: 0)
        XCTAssertEqual(issue.severity, .error)
    }

    func test_severity_unclosedCodeBlockIsError() {
        let issue = DocumentIssue(kind: .unclosedCodeBlock, fileURL: fileURL, line: 0)
        XCTAssertEqual(issue.severity, .error)
    }

    func test_severity_warnings() {
        let kinds: [DocumentIssue.Kind] = [
            .deadLink("x.md"), .duplicateHeading("T"),
            .headingLevelSkip(from: 1, to: 3), .emptyHeading
        ]
        for kind in kinds {
            XCTAssertEqual(DocumentIssue(kind: kind, fileURL: fileURL, line: 0).severity, .warning)
        }
    }
}
