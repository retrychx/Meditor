import XCTest
@testable import MEditor

@MainActor
final class GitStatusServiceTests: XCTestCase {

    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitStatusTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
        super.tearDown()
    }

    // MARK: - porcelain 解析

    /// 构造 -z 格式数据：记录以 NUL 分隔
    private func zdata(_ records: [String]) -> Data {
        Data(records.map { $0 + "\0" }.joined().utf8)
    }

    func test_parse_modified_stagedAndUnstaged() {
        let entries = GitStatusService.parsePorcelain(zdata([" M a.md", "M  b.md", "MM c.md"]))
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries[0].path, "a.md")
        XCTAssertEqual(entries[0].status, .modified)
        XCTAssertEqual(entries[1].status, .modified)
        XCTAssertEqual(entries[2].status, .modified)
    }

    func test_parse_added_andAddedWithModifications() {
        let entries = GitStatusService.parsePorcelain(zdata(["A  new.md", "AM newer.md"]))
        XCTAssertEqual(entries[0].status, .added)
        XCTAssertEqual(entries[1].status, .added, "AM（新增+追加改动）按新增显示")
    }

    func test_parse_untracked() {
        let entries = GitStatusService.parsePorcelain(zdata(["?? notes.md", "?? subdir/"]))
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].status, .untracked)
        XCTAssertEqual(entries[1].status, .untracked)
        XCTAssertEqual(entries[1].path, "subdir/")
    }

    func test_parse_deleted() {
        let entries = GitStatusService.parsePorcelain(zdata([" D gone.md", "D  staged-gone.md"]))
        XCTAssertEqual(entries.map(\.status), [.deleted, .deleted])
    }

    func test_parse_conflicted() {
        let entries = GitStatusService.parsePorcelain(zdata(["UU clash.md", "AA both.md", "DD both-gone.md"]))
        XCTAssertEqual(entries.map(\.status), [.conflicted, .conflicted, .conflicted])
    }

    func test_parse_ignored_isExcluded() {
        let entries = GitStatusService.parsePorcelain(zdata(["!! build/", " M a.md"]))
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].path, "a.md")
    }

    func test_parse_rename_consumesSourceRecord() {
        // -z 下重命名是两条记录：新路径 + 旧路径，旧路径不应产生独立条目
        let entries = GitStatusService.parsePorcelain(zdata(["R  new name.md", "old name.md", " M other.md"]))
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].path, "new name.md")
        XCTAssertEqual(entries[0].status, .renamed)
        XCTAssertEqual(entries[1].path, "other.md")
        XCTAssertEqual(entries[1].status, .modified)
    }

    func test_parse_filenamesWithSpacesAndCJK() {
        // -z 模式不做引号转义，空格/中文原样出现
        let entries = GitStatusService.parsePorcelain(zdata([" M my file.md", "?? 文档/未跟踪 笔记.md"]))
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].path, "my file.md")
        XCTAssertEqual(entries[1].path, "文档/未跟踪 笔记.md")
    }

    func test_parse_emptyAndGarbage() {
        XCTAssertTrue(GitStatusService.parsePorcelain(Data()).isEmpty)
        XCTAssertTrue(GitStatusService.parsePorcelain(zdata(["ab"])).isEmpty)  // 过短记录跳过
    }

    // MARK: - 工作区路径映射

    func test_map_workspaceIsRepoSubdir() {
        // 仓库根 /repo，工作区是 /repo/docs；仓库内其他目录的变更应被丢弃
        let repo = tempDir.appendingPathComponent("repo")
        let ws   = repo.appendingPathComponent("docs")
        let entries: [(path: String, status: GitFileStatus)] = [
            (path: "docs/guide.md", status: .modified),
            (path: "src/main.swift", status: .modified),   // 工作区外 → 丢弃
            (path: "README.md", status: .modified),        // 工作区外 → 丢弃
        ]
        let mapped = GitStatusService.mapToWorkspace(entries, repoRoot: repo, workspaceRoot: ws)
        XCTAssertEqual(mapped.statuses.count, 1)
        XCTAssertEqual(
            mapped.statuses[ws.appendingPathComponent("guide.md").standardizedFileURL],
            .modified
        )
        // 变更直接在根下：工作区根本身不进脏目录集合（根不在文件树显示）
        XCTAssertTrue(mapped.dirtyDirs.isEmpty)
    }

    func test_map_dirtyDirectoryAggregation() {
        let repo = tempDir.appendingPathComponent("repo")
        let entries: [(path: String, status: GitFileStatus)] = [
            (path: "a/b/deep.md", status: .modified),
            (path: "a/top.md", status: .untracked),
        ]
        let mapped = GitStatusService.mapToWorkspace(entries, repoRoot: repo, workspaceRoot: repo)
        XCTAssertEqual(mapped.statuses.count, 2)
        // a 和 a/b 都是脏目录；仓库根不是
        XCTAssertEqual(mapped.dirtyDirs.count, 2)
        XCTAssertTrue(mapped.dirtyDirs.contains(repo.appendingPathComponent("a").standardizedFileURL.path))
        XCTAssertTrue(mapped.dirtyDirs.contains(repo.appendingPathComponent("a/b").standardizedFileURL.path))
    }

    func test_map_untrackedDirectory_trailingSlashStripped() {
        let repo = tempDir.appendingPathComponent("repo")
        let entries: [(path: String, status: GitFileStatus)] = [
            (path: "newdir/", status: .untracked),
        ]
        let mapped = GitStatusService.mapToWorkspace(entries, repoRoot: repo, workspaceRoot: repo)
        XCTAssertEqual(
            mapped.statuses[repo.appendingPathComponent("newdir").standardizedFileURL],
            .untracked
        )
        XCTAssertTrue(mapped.dirtyDirs.isEmpty, "目录自身有状态，不再额外标脏父级")
    }

    // MARK: - 非 git 目录静默

    func test_findRepoRoot_nonGitDirectory_returnsNil() {
        XCTAssertNil(GitStatusService.findRepoRoot(of: tempDir),
                     "非 git 目录应静默返回 nil（除非 tempDir 恰好在某仓库内）")
    }

    func test_refreshNow_nonGitDirectory_staysSilent() async {
        let service = GitStatusService()
        service.refreshNow(rootURL: tempDir)
        // 等后台 Task 跑完：轮询一小段时间即可（非 git 目录结果为空态）
        try? await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertFalse(service.isGitWorkspace)
        XCTAssertTrue(service.statuses.isEmpty)
        XCTAssertTrue(service.directoryContainsChanges(tempDir) == false)
    }

    // MARK: - 真实仓库集成（git 可用时）

    func test_refreshNow_realRepo_detectsChanges() async throws {
        // git 不可用（沙箱/CI 极简环境）时跳过
        guard GitStatusService.runGit(["--version"], in: tempDir) != nil else {
            throw XCTSkip("git 不可用，跳过真实仓库集成测试")
        }
        let repo = tempDir.appendingPathComponent("realrepo")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)

        func git(_ args: [String]) {
            XCTAssertNotNil(GitStatusService.runGit(args, in: repo), "git \(args) 应成功")
        }

        git(["init"])
        git(["config", "user.email", "test@example.com"])
        git(["config", "user.name", "Test"])
        try "v1".write(to: repo.appendingPathComponent("tracked.md"), atomically: true, encoding: .utf8)
        git(["add", "."])
        git(["commit", "-m", "init"])

        // 制造三种状态：修改 / 暂存新增 / 未跟踪
        try "v2".write(to: repo.appendingPathComponent("tracked.md"), atomically: true, encoding: .utf8)
        try "new".write(to: repo.appendingPathComponent("staged.md"), atomically: true, encoding: .utf8)
        git(["add", "staged.md"])
        try "loose".write(to: repo.appendingPathComponent("untracked.md"), atomically: true, encoding: .utf8)

        let service = GitStatusService()
        service.refreshNow(rootURL: repo)

        // 后台 Task 完成前轮询，最多 5s
        let deadline = Date().addingTimeInterval(5)
        while service.statuses.count < 3 && Date() < deadline {
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        XCTAssertTrue(service.isGitWorkspace)
        XCTAssertEqual(service.status(for: repo.appendingPathComponent("tracked.md")), .modified)
        XCTAssertEqual(service.status(for: repo.appendingPathComponent("staged.md")), .added)
        XCTAssertEqual(service.status(for: repo.appendingPathComponent("untracked.md")), .untracked)
    }
}
