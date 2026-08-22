import XCTest
@testable import MEditor

final class PreviewAssetMirrorTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PreviewAssetMirrorTests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeFile(_ relative: String, contents: String = "x",
                          modificationDate: Date? = nil) -> URL {
        let url = tempDir.appendingPathComponent(relative)
        try! FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! contents.write(to: url, atomically: true, encoding: .utf8)
        if let modificationDate {
            try! FileManager.default.setAttributes(
                [.modificationDate: modificationDate], ofItemAtPath: url.path)
        }
        return url
    }

    // MARK: - shouldRefresh

    func test_shouldRefresh_sourceNewer_returnsTrue() {
        let src = makeFile("src.txt", modificationDate: Date(timeIntervalSince1970: 2000))
        let dst = makeFile("dst.txt", modificationDate: Date(timeIntervalSince1970: 1000))
        XCTAssertTrue(PreviewAssetMirror.shouldRefresh(src: src, dst: dst))
    }

    func test_shouldRefresh_destinationNewer_returnsFalse() {
        let src = makeFile("src.txt", modificationDate: Date(timeIntervalSince1970: 1000))
        let dst = makeFile("dst.txt", modificationDate: Date(timeIntervalSince1970: 2000))
        XCTAssertFalse(PreviewAssetMirror.shouldRefresh(src: src, dst: dst))
    }

    func test_shouldRefresh_sameDate_returnsFalse() {
        let date = Date(timeIntervalSince1970: 1000)
        let src = makeFile("src.txt", modificationDate: date)
        let dst = makeFile("dst.txt", modificationDate: date)
        XCTAssertFalse(PreviewAssetMirror.shouldRefresh(src: src, dst: dst))
    }

    func test_shouldRefresh_missingSource_returnsTrue() {
        let src = tempDir.appendingPathComponent("nonexistent.txt")
        let dst = makeFile("dst.txt")
        XCTAssertTrue(PreviewAssetMirror.shouldRefresh(src: src, dst: dst))
    }

    // MARK: - mirrorAssets

    /// Build a fake "bundle resources" directory containing a subset of
    /// `mirroredItems`, plus an unrelated file that must not be mirrored.
    private func makeSourceRoot() -> URL {
        let root = tempDir.appendingPathComponent("Source", isDirectory: true)
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try! "body{}".write(to: root.appendingPathComponent("css").appendingPathComponent("themes").appendingPathComponent("github.css"), atomically: true, encoding: .utf8)
        // createDirectory for nested css/themes first
        return root
    }

    private func makeBundleSource() -> URL {
        let root = tempDir.appendingPathComponent("BundlePreview", isDirectory: true)
        let cssDir = root.appendingPathComponent("css/themes", isDirectory: true)
        let scriptsDir = root.appendingPathComponent("scripts", isDirectory: true)
        try! FileManager.default.createDirectory(at: cssDir, withIntermediateDirectories: true)
        try! FileManager.default.createDirectory(at: scriptsDir, withIntermediateDirectories: true)
        try! "body{}".write(to: cssDir.appendingPathComponent("github.css"), atomically: true, encoding: .utf8)
        try! "console.log(1)".write(to: scriptsDir.appendingPathComponent("bridge.js"), atomically: true, encoding: .utf8)
        try! "marked".write(to: root.appendingPathComponent("marked.min.js"), atomically: true, encoding: .utf8)
        try! "hljs".write(to: root.appendingPathComponent("highlight.min.js"), atomically: true, encoding: .utf8)
        try! "SHOULD-NOT-MIRROR".write(to: root.appendingPathComponent("mermaid.min.js"), atomically: true, encoding: .utf8)
        return root
    }

    func test_mirrorAssets_copiesAllMirroredItems() throws {
        let source = makeBundleSource()
        let cache = tempDir.appendingPathComponent("Cache", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)

        PreviewAssetMirror.mirrorAssets(at: cache, copyingFrom: source)

        let fm = FileManager.default
        for item in PreviewAssetMirror.mirroredItems {
            XCTAssertTrue(fm.fileExists(atPath: cache.appendingPathComponent(item).path),
                          "expected \(item) to be mirrored")
        }
        XCTAssertEqual(try String(contentsOf: cache.appendingPathComponent("css/themes/github.css"), encoding: .utf8), "body{}")
        // mermaid.min.js must NOT be mirrored eagerly.
        XCTAssertFalse(fm.fileExists(atPath: cache.appendingPathComponent("mermaid.min.js").path))
    }

    func test_mirrorAssets_skipsMissingSourceItems() throws {
        let source = tempDir.appendingPathComponent("SparseSource", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try "marked".write(to: source.appendingPathComponent("marked.min.js"), atomically: true, encoding: .utf8)
        let cache = tempDir.appendingPathComponent("SparseCache", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)

        PreviewAssetMirror.mirrorAssets(at: cache, copyingFrom: source)

        let fm = FileManager.default
        XCTAssertTrue(fm.fileExists(atPath: cache.appendingPathComponent("marked.min.js").path))
        XCTAssertFalse(fm.fileExists(atPath: cache.appendingPathComponent("css").path))
    }

    func test_mirrorAssets_refreshesStaleDestination() throws {
        let source = makeBundleSource()
        let cache = tempDir.appendingPathComponent("StaleCache", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)

        // Pre-existing stale copy: plain file (not a hard link) with an old mtime.
        let staleMarked = cache.appendingPathComponent("marked.min.js")
        try "OLD".write(to: staleMarked, atomically: true, encoding: .utf8)
        let old = Date(timeIntervalSince1970: 1000)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: staleMarked.path)
        // Make sure the source reads newer than the stale copy.
        let srcMarked = source.appendingPathComponent("marked.min.js")
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 2000)], ofItemAtPath: srcMarked.path)

        PreviewAssetMirror.mirrorAssets(at: cache, copyingFrom: source)

        XCTAssertEqual(try String(contentsOf: staleMarked, encoding: .utf8), "marked")
    }

    func test_mirrorAssets_keepsUpToDateDestination() throws {
        let source = makeBundleSource()
        let cache = tempDir.appendingPathComponent("FreshCache", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)

        // Destination newer than source → must be left untouched.
        let dstMarked = cache.appendingPathComponent("marked.min.js")
        try "CUSTOM".write(to: dstMarked, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 3000)], ofItemAtPath: dstMarked.path)
        let srcMarked = source.appendingPathComponent("marked.min.js")
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 2000)], ofItemAtPath: srcMarked.path)

        PreviewAssetMirror.mirrorAssets(at: cache, copyingFrom: source)

        XCTAssertEqual(try String(contentsOf: dstMarked, encoding: .utf8), "CUSTOM")
    }

    // MARK: - pruneCacheIfNeeded

    func test_pruneCache_underLimit_keepsDirectory() throws {
        let dir = tempDir.appendingPathComponent("SmallCache", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "tiny".write(to: dir.appendingPathComponent("preview.html"), atomically: true, encoding: .utf8)

        PreviewAssetMirror.pruneCacheIfNeeded(at: dir, sizeLimit: 1024 * 1024)

        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("preview.html").path))
    }

    func test_pruneCache_overLimit_wipesDirectory() throws {
        let dir = tempDir.appendingPathComponent("BigCache", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try String(repeating: "x", count: 4096).write(to: dir.appendingPathComponent("preview.html"), atomically: true, encoding: .utf8)

        PreviewAssetMirror.pruneCacheIfNeeded(at: dir, sizeLimit: 1)

        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
    }

    func test_pruneCache_missingDirectory_noOp() {
        let dir = tempDir.appendingPathComponent("NoSuchDir", isDirectory: true)
        // Must not crash or create anything.
        PreviewAssetMirror.pruneCacheIfNeeded(at: dir, sizeLimit: 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
    }

    // MARK: - jsonEncode

    func test_jsonEncode_producesValidJSONStringLiteral() throws {
        let encoded = try XCTUnwrap(PreviewAssetMirror.jsonEncode(string: "hello \"world\"\nline2"))
        let data = try XCTUnwrap(encoded.data(using: .utf8))
        let decoded = try JSONDecoder().decode(String.self, from: data)
        XCTAssertEqual(decoded, "hello \"world\"\nline2")
    }
}
