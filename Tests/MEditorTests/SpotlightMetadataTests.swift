import CoreSpotlight
import XCTest
@testable import MEditor

/// Spotlight 索引纯逻辑测试：标题/摘要/截断提取、domainIdentifier、
/// 索引项构造、增量 diff。断言全部与语言无关（CI 英文 locale）。
final class SpotlightMetadataTests: XCTestCase {

    // MARK: - Title extraction

    func testTitleFromFirstH1() {
        let md = "\nSome intro\n# Hello World\n\nbody\n"
        let meta = SpotlightMetadata.extract(from: md, fileName: "note.md")
        XCTAssertEqual(meta.title, "Hello World")
    }

    func testTitlePrefersFirstH1OverLaterOnes() {
        let md = "# First\n\n## Sub\n\n# Second\n"
        XCTAssertEqual(SpotlightMetadata.firstH1(in: md), "First")
    }

    func testTitleStripsClosingHashes() {
        XCTAssertEqual(SpotlightMetadata.firstH1(in: "# Title ##"), "Title")
    }

    func testTitleIgnoresH2AndLower() {
        let md = "## Subtitle\n\ncontent\n"
        XCTAssertNil(SpotlightMetadata.firstH1(in: md))
    }

    func testTitleFallsBackToFileNameWithoutExtension() {
        let meta = SpotlightMetadata.extract(from: "no heading here\n", fileName: "Meeting Notes.md")
        XCTAssertEqual(meta.title, "Meeting Notes")
    }

    func testTitleIgnoresH1InsideFencedCodeBlock() {
        let md = "```\n# Not A Heading\n```\n\n# Real Heading\n"
        XCTAssertEqual(SpotlightMetadata.firstH1(in: md), "Real Heading")
    }

    func testTitleWithLeadingWhitespaceBeforeHash() {
        XCTAssertEqual(SpotlightMetadata.firstH1(in: "   # Indented Title"), "Indented Title")
    }

    // MARK: - Description extraction

    func testDescriptionFromFirstParagraphLine() {
        let md = "# Title\n\nFirst paragraph line.\nSecond line.\n"
        let meta = SpotlightMetadata.extract(from: md, fileName: "a.md")
        XCTAssertEqual(meta.contentDescription, "First paragraph line.")
    }

    func testDescriptionSkipsEmptyHeadingAndFenceLines() {
        let md = "\n\n# Title\n```swift\ncode\n"
        XCTAssertEqual(SpotlightMetadata.firstParagraph(in: md), "code")
    }

    func testDescriptionEmptyDocument() {
        XCTAssertEqual(SpotlightMetadata.firstParagraph(in: ""), "")
        XCTAssertEqual(SpotlightMetadata.firstParagraph(in: "# Only Heading\n"), "")
    }

    func testDescriptionTruncatedToMaxLength() {
        let longLine = String(repeating: "x", count: SpotlightMetadata.maxDescriptionLength + 50)
        let result = SpotlightMetadata.firstParagraph(in: longLine)
        XCTAssertEqual(result.count, SpotlightMetadata.maxDescriptionLength)
    }

    // MARK: - Text content truncation

    func testTextContentNotTruncatedWhenShort() {
        let md = "# Title\n\nshort body\n"
        let meta = SpotlightMetadata.extract(from: md, fileName: "a.md")
        XCTAssertEqual(meta.textContent, md)
    }

    func testTextContentTruncatedWhenLong() {
        let md = String(repeating: "y", count: SpotlightMetadata.maxTextContentLength + 1000)
        let meta = SpotlightMetadata.extract(from: md, fileName: "a.md")
        XCTAssertEqual(meta.textContent.count, SpotlightMetadata.maxTextContentLength)
    }

    // MARK: - Domain identifier

    func testDomainIdentifierStableForSamePath() {
        let url = URL(fileURLWithPath: "/tmp/workspace")
        XCTAssertEqual(
            SpotlightMetadata.domainIdentifier(forRoot: url),
            SpotlightMetadata.domainIdentifier(forRoot: url)
        )
        XCTAssertTrue(SpotlightMetadata.domainIdentifier(forRoot: url).hasPrefix("workspace-"))
    }

    func testDomainIdentifierDiffersAcrossPaths() {
        XCTAssertNotEqual(
            SpotlightMetadata.domainIdentifier(forRoot: URL(fileURLWithPath: "/tmp/a")),
            SpotlightMetadata.domainIdentifier(forRoot: URL(fileURLWithPath: "/tmp/b"))
        )
    }

    func testDomainIdentifierNormalizesTrailingSlash() {
        XCTAssertEqual(
            SpotlightMetadata.domainIdentifier(forRoot: URL(fileURLWithPath: "/tmp/ws/")),
            SpotlightMetadata.domainIdentifier(forRoot: URL(fileURLWithPath: "/tmp/ws"))
        )
    }

    // MARK: - Item builder

    func testMakeItemCarriesIdentifierDomainAndAttributes() {
        let url = URL(fileURLWithPath: "/tmp/ws/doc.md")
        let meta = SpotlightDocumentMetadata(title: "T", contentDescription: "D", textContent: "C")
        let modDate = Date(timeIntervalSince1970: 1_700_000_000)
        let item = SpotlightItemBuilder.makeItem(
            url: url, domainIdentifier: "workspace-abc", metadata: meta, contentModificationDate: modDate)
        XCTAssertEqual(item.uniqueIdentifier, "/tmp/ws/doc.md")
        XCTAssertEqual(item.domainIdentifier, "workspace-abc")
        XCTAssertEqual(item.attributeSet.title, "T")
        XCTAssertEqual(item.attributeSet.contentDescription, "D")
        XCTAssertEqual(item.attributeSet.textContent, "C")
        XCTAssertEqual(item.attributeSet.contentModificationDate, modDate)
    }

    // MARK: - Differ

    func testDiffNewModifiedDeletedAndUnchanged() {
        let date1 = Date(timeIntervalSince1970: 100)
        let date2 = Date(timeIntervalSince1970: 200)
        let disk: [String: Date?] = [
            "/w/unchanged.md": date1,
            "/w/modified.md": date2,
            "/w/new.md": date1,
        ]
        let indexed: [String: Date?] = [
            "/w/unchanged.md": date1,
            "/w/modified.md": date1,
            "/w/deleted.md": date1,
        ]
        let changes = SpotlightIndexDiffer.diff(disk: disk, indexed: indexed)
        XCTAssertEqual(changes.upsert, ["/w/modified.md", "/w/new.md"])
        XCTAssertEqual(changes.delete, ["/w/deleted.md"])
    }

    func testDiffEmptyDiskDeletesEverything() {
        let indexed: [String: Date?] = ["/w/a.md": nil]
        let changes = SpotlightIndexDiffer.diff(disk: [:], indexed: indexed)
        XCTAssertEqual(changes.delete, ["/w/a.md"])
        XCTAssertTrue(changes.upsert.isEmpty)
    }

    func testDiffEmptyIndexedUpsertsEverything() {
        let disk: [String: Date?] = ["/w/a.md": nil, "/w/b.md": nil]
        let changes = SpotlightIndexDiffer.diff(disk: disk, indexed: [:])
        XCTAssertEqual(changes.upsert, ["/w/a.md", "/w/b.md"])
        XCTAssertTrue(changes.delete.isEmpty)
    }
}
