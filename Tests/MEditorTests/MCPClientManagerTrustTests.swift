import XCTest
@testable import MEditor

/// 工作区级 `.meditor/mcp.json` 的信任门禁：
/// 不可信仓库的配置在授权前不得被加载/连接（否则 agent 一启动就 RCE）。
@MainActor
final class MCPClientManagerTrustTests: XCTestCase {

    private var base: URL!
    private var workspace: URL!
    private var workspaceConfig: URL!
    private var globalConfig: URL!
    private let serverName = "evil"

    override func setUp() async throws {
        try await super.setUp()
        base = FileManager.default.temporaryDirectory
            .appendingPathComponent("meditor-mcp-trust-\(UUID().uuidString)")
        workspace = base.appendingPathComponent("workspace")
        try FileManager.default.createDirectory(
            at: workspace.appendingPathComponent(".meditor"), withIntermediateDirectories: true)
        workspaceConfig = MCPClientConfigLoader.workspaceConfigURL(root: workspace)
        globalConfig = base.appendingPathComponent("missing-global.json")
        try writeWorkspaceConfig(command: "/bin/echo")
        AppSettings.shared.revokeWorkspaceMCP(workspacePath: workspace.standardizedFileURL.path)
    }

    override func tearDown() async throws {
        AppSettings.shared.revokeWorkspaceMCP(workspacePath: workspace.standardizedFileURL.path)
        try? FileManager.default.removeItem(at: base)
        try await super.tearDown()
    }

    private func writeWorkspaceConfig(command: String) throws {
        let json = """
        {"mcpServers": {"\(serverName)": {"command": "\(command)", "args": ["hi"]}}}
        """
        try json.write(to: workspaceConfig, atomically: true, encoding: .utf8)
    }

    private func makeManager() -> MCPClientManager { MCPClientManager() }

    func test_workspaceConfigIgnoredUntilTrusted() {
        let manager = makeManager()
        manager.reloadConfigSummaries(workspaceURL: workspace, globalConfigURL: globalConfig)

        guard let info = manager.workspaceMCPInfo else { return XCTFail("应识别到工作区配置") }
        XCTAssertFalse(info.trusted, "默认不得信任工作区配置")
        XCTAssertEqual(info.serverNames, [serverName])
        XCTAssertFalse(manager.statuses.contains { $0.name == serverName },
                       "未授权的工作区 server 不得进入状态/连接列表")
        XCTAssertTrue(manager.configIssues.contains { $0.contains("ignored") },
                      "未授权时应给出可见提示，而不是静默忽略")
    }

    func test_trustedWorkspaceConfigIsLoaded() throws {
        let hash = try XCTUnwrap(MCPClientConfigLoader.workspaceConfigHash(root: workspace))
        AppSettings.shared.trustWorkspaceMCP(workspacePath: workspace.standardizedFileURL.path, configHash: hash)

        let manager = makeManager()
        manager.reloadConfigSummaries(workspaceURL: workspace, globalConfigURL: globalConfig)

        XCTAssertEqual(manager.workspaceMCPInfo?.trusted, true)
        XCTAssertTrue(manager.statuses.contains { $0.name == serverName },
                      "授权后工作区 server 应出现在配置列表中")
    }

    func test_trustRevokedWhenConfigContentChanges() throws {
        let hash = try XCTUnwrap(MCPClientConfigLoader.workspaceConfigHash(root: workspace))
        AppSettings.shared.trustWorkspaceMCP(workspacePath: workspace.standardizedFileURL.path, configHash: hash)

        // 配置被换成另一条命令 → hash 不匹配 → 信任自动失效
        try writeWorkspaceConfig(command: "/bin/rm")

        let manager = makeManager()
        manager.reloadConfigSummaries(workspaceURL: workspace, globalConfigURL: globalConfig)

        XCTAssertEqual(manager.workspaceMCPInfo?.trusted, false)
        XCTAssertFalse(manager.statuses.contains { $0.name == serverName })
    }

    func test_workspaceConfigHashDiffersForDifferentContent() throws {
        let hash1 = try XCTUnwrap(MCPClientConfigLoader.workspaceConfigHash(root: workspace))
        try writeWorkspaceConfig(command: "/bin/echo changed")
        let hash2 = try XCTUnwrap(MCPClientConfigLoader.workspaceConfigHash(root: workspace))
        XCTAssertNotEqual(hash1, hash2)
    }
}
