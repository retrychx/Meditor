import XCTest
@testable import MEditor

// MARK: - MCPToolTests
//
// 覆盖：
//   - 工具名清洗（[a-zA-Z0-9_-]）与 mcp__<server>__<tool> 前缀映射
//   - inputSchema 原文透传（openAIDict / anthropicDict 保留嵌套结构）
//   - 确认链路：每 server 每会话首次调用确认一次；拒绝时不触达远端
//   - tools/call 结果渲染（text 直取 / 其他类型序列化 JSON / isError 抛错）
//
// 注意：CI 是英文 locale，断言不写死中文文案。

/// 内存 stub 传输：按 method 回放预置 result，记录 tools/call 调用次数。
private actor StubMCPTransport: MCPClientTransport {
    var responses: [String: [String: Any]] = [:]
    private(set) var callCount = 0
    private(set) var notified: [String] = []
    private(set) var closed = false

    func request(method: String, params: [String: Any], timeout: TimeInterval) async throws -> [String: Any] {
        if method == "tools/call" { callCount += 1 }
        if let canned = responses[method] { return canned }
        throw MCPError(code: MCPJSONRPC.methodNotFoundCode, message: "stub: no canned response for \(method)")
    }

    func notify(method: String, params: [String: Any]) async { notified.append(method) }
    func close() async { closed = true }
}

final class MCPToolTests: XCTestCase {

    // MARK: - Helpers

    /// 组装一个已连接的 client（initialize/tools/list 走 stub 回放）。
    private func makeConnectedClient(stub: StubMCPTransport) async throws -> MCPClient {
        await stub.setResponses([
            "initialize": ["protocolVersion": "2025-03-26", "capabilities": [:], "serverInfo": ["name": "fake", "version": "1.0"]],
            "tools/list": ["tools": [[
                "name": "echo",
                "description": "Echo input",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "text": ["type": "string", "description": "text to echo"],
                        "tags": ["type": "array", "items": ["type": "string"]] as [String: Any],
                    ],
                    "required": ["text"],
                ],
            ]]],
            "tools/call": ["content": [["type": "text", "text": "pong"]]],
        ])
        let config = MCPServerConfig(name: "srv", kind: .http(url: URL(string: "https://stub.local/mcp")!))
        let client = MCPClient(config: config) { _ in stub }
        try await client.connect()
        return client
    }

    // MARK: - 命名

    func test_sanitize_keepsAllowedChars() {
        XCTAssertEqual(MCPTool.sanitize("my-server_2"), "my-server_2")
    }

    func test_sanitize_replacesDisallowedChars() {
        XCTAssertEqual(MCPTool.sanitize("my server!@#x"), "my_server_x")
        XCTAssertEqual(MCPTool.sanitize("...dots..."), "dots")
    }

    func test_sanitize_emptyAfterCleaning_fallsBack() {
        XCTAssertEqual(MCPTool.sanitize("！！！"), "x")
    }

    func test_registeredName_prefixMapping() {
        XCTAssertEqual(MCPTool.registeredName(server: "fs", tool: "read_file"), "mcp__fs__read_file")
        XCTAssertEqual(MCPTool.registeredName(server: "my server", tool: "do.it"),
                       "mcp__my_server__do_it")
        XCTAssertTrue(MCPTool.registeredName(server: "fs", tool: "x").hasPrefix("mcp__"))
    }

    func test_registeredName_truncatedTo64() {
        let long = String(repeating: "a", count: 100)
        XCTAssertEqual(MCPTool.registeredName(server: long, tool: long).count, 64)
    }

    // MARK: - inputSchema 透传

    func test_spec_rawSchemaPassthrough() async throws {
        let stub = StubMCPTransport()
        let client = try await makeConnectedClient(stub: stub)
        let remoteTools = await client.tools
        let remote = try XCTUnwrap(remoteTools.first)
        let tool = MCPTool(registeredName: "mcp__srv__echo", serverName: "srv", remote: remote, client: client)

        XCTAssertEqual(tool.spec.name, "mcp__srv__echo")
        XCTAssertEqual(tool.spec.description, "Echo input")

        // OpenAI wire：parameters 原文透传（含嵌套 items，ToolPropertySchema 表达不了的结构不丢）
        let openAI = tool.spec.openAIDict
        let function = try XCTUnwrap(openAI["function"] as? [String: Any])
        let params = try XCTUnwrap(function["parameters"] as? [String: Any])
        let props = try XCTUnwrap(params["properties"] as? [String: Any])
        let tags = try XCTUnwrap(props["tags"] as? [String: Any])
        XCTAssertEqual(tags["type"] as? String, "array")
        XCTAssertEqual((tags["items"] as? [String: Any])?["type"] as? String, "string")
        XCTAssertEqual(params["required"] as? [String], ["text"])

        // Anthropic wire：input_schema 同样透传
        let anthropic = tool.spec.anthropicDict
        let inputSchema = try XCTUnwrap(anthropic["input_schema"] as? [String: Any])
        XCTAssertEqual(inputSchema["type"] as? String, "object")
        XCTAssertNotNil((inputSchema["properties"] as? [String: Any])?["text"])

        // 降级表示：顶层属性转 ToolParameterSchema（ClaudeCLI 紧凑签名等展示路径用）
        XCTAssertEqual(tool.spec.parameters.required, ["text"])
        XCTAssertTrue(tool.spec.parameters.orderedProperties.contains { $0.key == "tags" })
        XCTAssertTrue(tool.spec.compactCLIDescription.contains("mcp__srv__echo"))
    }

    // MARK: - 确认链路

    @MainActor
    func test_execute_firstCallAsksConfirmation_oncePerServerPerSession() async throws {
        let stub = StubMCPTransport()
        let client = try await makeConnectedClient(stub: stub)
        let remoteTools = await client.tools
        let remote = try XCTUnwrap(remoteTools.first)
        let tool = MCPTool(registeredName: "mcp__srv__echo", serverName: "srv", remote: remote, client: client)

        let context = MockAgentContext()
        context.commandConfirmResult = true

        let first = try await tool.execute(arguments: ["text": .string("hi")], context: context)
        XCTAssertEqual(first, "pong")
        XCTAssertEqual(context.confirmedCommands.count, 1, "首次调用应弹一次确认")
        XCTAssertTrue(context.confirmedCommands[0].contains("srv"))

        // 同会话第二次调用：命中审批缓存，不再弹框
        let second = try await tool.execute(arguments: ["text": .string("again")], context: context)
        XCTAssertEqual(second, "pong")
        XCTAssertEqual(context.confirmedCommands.count, 1, "会话内同 server 不应重复确认")
        let calls = await stub.callCount
        XCTAssertEqual(calls, 2)
    }

    @MainActor
    func test_execute_userDeclines_noRemoteCall() async throws {
        let stub = StubMCPTransport()
        let client = try await makeConnectedClient(stub: stub)
        let remoteTools = await client.tools
        let remote = try XCTUnwrap(remoteTools.first)
        let tool = MCPTool(registeredName: "mcp__srv__echo", serverName: "srv", remote: remote, client: client)

        let context = MockAgentContext()
        context.commandConfirmResult = false

        let result = try await tool.execute(arguments: ["text": .string("hi")], context: context)
        XCTAssertTrue(result.hasPrefix("[!]"))
        let calls = await stub.callCount
        XCTAssertEqual(calls, 0, "用户拒绝时不得触达远端")
    }

    // MARK: - 结果渲染

    func test_renderContent_textItemsJoined() {
        let content: [[String: Any]] = [
            ["type": "text", "text": "line1"],
            ["type": "text", "text": "line2"],
        ]
        XCTAssertEqual(MCPClient.renderContent(content), "line1\nline2")
    }

    func test_renderContent_nonTextSerializedAsJSON() {
        let content: [[String: Any]] = [
            ["type": "image", "data": "aGVsbG8=", "mimeType": "image/png"],
        ]
        let rendered = MCPClient.renderContent(content)
        XCTAssertTrue(rendered.contains("\"type\":\"image\""))
        // Foundation 的 JSONSerialization 会把 "/" 转义为 "\/"，不断言 mimeType 的值，只查键在
        XCTAssertTrue(rendered.contains("mimeType"))
    }

    func test_renderContent_empty() {
        XCTAssertEqual(MCPClient.renderContent(nil), "(empty result)")
        XCTAssertEqual(MCPClient.renderContent([]), "(empty result)")
    }

    @MainActor
    func test_callTool_remoteIsError_throws() async throws {
        let stub = StubMCPTransport()
        await stub.setResponses([
            "initialize": ["protocolVersion": "2025-03-26"],
            "tools/list": ["tools": [["name": "boom", "inputSchema": ["type": "object"]]]],
            "tools/call": ["content": [["type": "text", "text": "remote blew up"]], "isError": true],
        ])
        let config = MCPServerConfig(name: "srv", kind: .http(url: URL(string: "https://stub.local/mcp")!))
        let client = MCPClient(config: config) { _ in stub }
        try await client.connect()

        do {
            _ = try await client.callTool(name: "boom", arguments: [:])
            XCTFail("isError result should throw")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("remote blew up"))
        }
    }

    // MARK: - tools/list 解析容错

    func test_parseToolList_skipsBadEntries() {
        let result: [String: Any] = ["tools": [
            ["name": "good", "description": "d", "inputSchema": ["type": "object"]],
            ["description": "missing name"],          // 缺 name → 跳过
            "not-an-object",                            // 非对象 → 跳过（as? 过滤）
        ]]
        // [["String": Any]] 强转过滤掉非对象元素
        let tools = MCPClient.parseToolList(result)
        XCTAssertEqual(tools.map(\.name), ["good"])
    }
}

// MARK: - StubMCPTransport 测试辅助

private extension StubMCPTransport {
    func setResponses(_ responses: [String: [String: Any]]) {
        self.responses = responses
    }
}
