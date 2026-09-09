import XCTest
@testable import MEditor

// MARK: - MCPClientConfigTests
//
// 覆盖 mcp.json 配置解析：
//   - 合法 stdio / http 条目
//   - 非法 JSON / 非对象 root / mcpServers 类型错误
//   - 坏条目跳过并记录 issue（不拖垮整个加载）
//   - 工作区配置覆盖全局同名条目
//
// 注意：CI 是英文 locale，断言只查结构性内容与 ASCII 片段。

final class MCPClientConfigTests: XCTestCase {

    var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("meditor-mcp-client-cfg-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempRoot { try? FileManager.default.removeItem(at: tempRoot) }
        tempRoot = nil
    }

    private func write(_ content: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - 合法配置

    func test_parse_stdioServer() throws {
        let json = """
        {"mcpServers": {"fs": {"command": "npx", "args": ["-y", "@mcp/fs"], "env": {"KEY": "v"}}}}
        """
        let result = MCPClientConfigLoader.parse(data: Data(json.utf8), source: "test")
        XCTAssertTrue(result.issues.isEmpty)
        XCTAssertEqual(result.servers.count, 1)
        let server = try XCTUnwrap(result.servers.first)
        XCTAssertEqual(server.name, "fs")
        XCTAssertEqual(server.kindLabel, "stdio")
        guard case .stdio(let command, let args, let env) = server.kind else {
            return XCTFail("expected stdio kind")
        }
        XCTAssertEqual(command, "npx")
        XCTAssertEqual(args, ["-y", "@mcp/fs"])
        XCTAssertEqual(env, ["KEY": "v"])
    }

    func test_parse_httpServer() throws {
        let json = """
        {"mcpServers": {"remote": {"url": "https://example.com/mcp"}}}
        """
        let result = MCPClientConfigLoader.parse(data: Data(json.utf8), source: "test")
        XCTAssertTrue(result.issues.isEmpty)
        let server = try XCTUnwrap(result.servers.first)
        XCTAssertEqual(server.kindLabel, "http")
        guard case .http(let url) = server.kind else {
            return XCTFail("expected http kind")
        }
        XCTAssertEqual(url.absoluteString, "https://example.com/mcp")
    }

    // MARK: - 容错

    func test_parse_invalidJSON_recordsIssue() {
        let result = MCPClientConfigLoader.parse(data: Data("not json".utf8), source: "global")
        XCTAssertTrue(result.servers.isEmpty)
        XCTAssertEqual(result.issues.count, 1)
        XCTAssertTrue(result.issues[0].contains("global"))
    }

    func test_parse_rootNotObject_recordsIssue() {
        let result = MCPClientConfigLoader.parse(data: Data("[1,2]".utf8), source: "global")
        XCTAssertTrue(result.servers.isEmpty)
        XCTAssertFalse(result.issues.isEmpty)
    }

    func test_parse_missingMCPServersKey_empty() {
        let result = MCPClientConfigLoader.parse(data: Data("{}".utf8), source: "global")
        XCTAssertTrue(result.servers.isEmpty)
        XCTAssertTrue(result.issues.isEmpty)   // 空配置是合法状态，不算坏条目
    }

    func test_parse_badEntriesSkipped_goodEntrySurvives() throws {
        let json = """
        {
          "mcpServers": {
            "ok": {"url": "https://example.com/mcp"},
            "noCommandNoURL": {"args": []},
            "badURL": {"url": "not a url with spaces"},
            "notAnObject": "just-a-string",
            "badArgs": {"command": "npx", "args": [{"nested": true}]}
          }
        }
        """
        let result = MCPClientConfigLoader.parse(data: Data(json.utf8), source: "ws")
        XCTAssertEqual(result.servers.map(\.name), ["ok"])
        // 4 个坏条目各记一条 issue
        XCTAssertEqual(result.issues.count, 4)
        XCTAssertTrue(result.issues.allSatisfy { $0.contains("skipped") })
    }

    func test_parse_envNonScalarValuesDropped() throws {
        let json = """
        {"mcpServers": {"s": {"command": "x", "env": {"A": "1", "B": 2, "C": {"bad": true}}}}}
        """
        let result = MCPClientConfigLoader.parse(data: Data(json.utf8), source: "t")
        let server = try XCTUnwrap(result.servers.first)
        guard case .stdio(_, _, let env) = server.kind else { return XCTFail("expected stdio") }
        XCTAssertEqual(env, ["A": "1", "B": "2"])   // 非标量值丢弃，数字字符串化
    }

    // MARK: - 合并（工作区覆盖全局）

    func test_load_workspaceOverridesGlobal() throws {
        let globalURL = tempRoot.appendingPathComponent("global/mcp.json")
        try write("""
        {"mcpServers": {
          "shared": {"command": "global-bin"},
          "globalOnly": {"url": "https://global.example.com/mcp"}
        }}
        """, to: globalURL)

        let workspace = tempRoot.appendingPathComponent("workspace", isDirectory: true)
        let wsURL = MCPClientConfigLoader.workspaceConfigURL(root: workspace)
        try write("""
        {"mcpServers": {
          "shared": {"url": "https://workspace.example.com/mcp"},
          "wsOnly": {"command": "ws-bin"}
        }}
        """, to: wsURL)

        let result = MCPClientConfigLoader.load(globalConfigURL: globalURL, workspaceRoot: workspace)
        XCTAssertTrue(result.issues.isEmpty)
        XCTAssertEqual(Set(result.servers.map(\.name)), ["shared", "globalOnly", "wsOnly"])

        let shared = try XCTUnwrap(result.servers.first { $0.name == "shared" })
        guard case .http(let url) = shared.kind else {
            return XCTFail("workspace entry should override global same-name entry")
        }
        XCTAssertEqual(url.host, "workspace.example.com")

        let globalOnly = try XCTUnwrap(result.servers.first { $0.name == "globalOnly" })
        guard case .http = globalOnly.kind else { return XCTFail("globalOnly should stay http") }
    }

    func test_load_missingFiles_empty() {
        let result = MCPClientConfigLoader.load(
            globalConfigURL: tempRoot.appendingPathComponent("nope/mcp.json"),
            workspaceRoot: tempRoot.appendingPathComponent("nope-ws"))
        XCTAssertTrue(result.servers.isEmpty)
        XCTAssertTrue(result.issues.isEmpty)
    }
}
