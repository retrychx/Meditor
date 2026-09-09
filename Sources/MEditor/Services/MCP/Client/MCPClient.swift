import Foundation

// MARK: - MCPClient（单个 server 的会话：initialize → tools/list 缓存 → tools/call）
//
// 协议流程（protocolVersion "2025-03-26"）：
//   1. initialize 握手（clientInfo name "MEditor"）
//   2. notifications/initialized 通知（尽力而为）
//   3. tools/list 拉取并缓存工具清单
//   4. tools/call 按需调用
// 懒连接：connect() 由 MCPClientManager 在 agent run 开始时触发，不随配置加载自动连接。

/// 远端工具清单里的一项（tools/list 的元素）。
struct MCPRemoteTool: Sendable {
    var name: String
    var description: String
    /// 远端 inputSchema 原文（任意 JSON Schema），注册时透传给后端
    var inputSchema: [String: AnySendableValue]
}

/// MCP 客户端错误（传输层错误见 MCPTransportError / MCPError）。
enum MCPClientError: LocalizedError {
    case notConnected
    case unsupportedTransport(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "MCP client is not connected"
        case .unsupportedTransport(let detail):
            return "MCP transport unavailable: \(detail)"
        }
    }
}

actor MCPClient {

    /// 握手声明的协议版本（与任务约定一致；服务端版本不强制校验，宽容互联）
    static let protocolVersion = "2025-03-26"
    /// initialize / tools/list 超时
    static let handshakeTimeout: TimeInterval = 30
    /// 单次 tools/call 超时
    static let callTimeout: TimeInterval = 60

    let config: MCPServerConfig
    private let transportFactory: @Sendable (MCPServerConfig) throws -> any MCPClientTransport
    private var transport: (any MCPClientTransport)?
    /// tools/list 缓存（连接期间不变；重连后刷新）
    private(set) var tools: [MCPRemoteTool] = []

    init(config: MCPServerConfig,
         transportFactory: @escaping @Sendable (MCPServerConfig) throws -> any MCPClientTransport = MCPClient.defaultTransport) {
        self.config = config
        self.transportFactory = transportFactory
    }

    /// 默认传输工厂：stdio 仅 macOS 可用（iOS 无 Process 子进程能力）。
    static func defaultTransport(for config: MCPServerConfig) throws -> any MCPClientTransport {
        switch config.kind {
        case .stdio(let command, let args, let env):
#if os(macOS)
            return try MCPStdioTransport(command: command, args: args, env: env)
#else
            throw MCPClientError.unsupportedTransport("stdio requires macOS")
#endif
        case .http(let url):
            return MCPStreamableHTTPTransport(url: url)
        }
    }

    var isConnected: Bool { transport != nil }

    /// 连接并完成握手 + 工具清单拉取。失败时关闭传输并抛错（调用方降级处理）。
    func connect() async throws {
        let t = try transportFactory(config)
        do {
            _ = try await t.request(method: "initialize", params: [
                "protocolVersion": Self.protocolVersion,
                "capabilities": [:] as [String: Any],
                "clientInfo": [
                    "name": "MEditor",
                    "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev",
                ] as [String: Any],
            ], timeout: Self.handshakeTimeout)
            await t.notify(method: "notifications/initialized", params: [:])
            let list = try await t.request(method: "tools/list", params: [:], timeout: Self.handshakeTimeout)
            tools = Self.parseToolList(list)
            transport = t
        } catch {
            await t.close()
            throw error
        }
    }

    /// 调用远端工具，返回拼接后的文本结果。
    /// 远端返回 isError: true 时抛 AgentError.executionError（让 Runner 记为工具失败）。
    func callTool(name: String, arguments: [String: Any]) async throws -> String {
        guard let transport else { throw MCPClientError.notConnected }
        let result = try await transport.request(method: "tools/call", params: [
            "name": name,
            "arguments": arguments,
        ], timeout: Self.callTimeout)
        let text = Self.renderContent(result["content"])
        if result["isError"] as? Bool == true {
            throw AgentError.executionError(text)
        }
        return text
    }

    func close() async {
        await transport?.close()
        transport = nil
        tools = []
    }

    // MARK: - 纯逻辑（可单测）

    /// 解析 tools/list 结果里的工具数组。坏条目跳过（缺 name 等），不拖垮整个清单。
    /// 注意先转 [Any] 再逐个转字典：真实 JSON 里混入非对象元素时，
    /// `as? [[String: Any]]` 会让整个数组 cast 失败。
    static func parseToolList(_ result: [String: Any]) -> [MCPRemoteTool] {
        guard let rawTools = result["tools"] as? [Any] else { return [] }
        return rawTools.compactMap { element -> MCPRemoteTool? in
            guard let raw = element as? [String: Any],
                  let name = raw["name"] as? String, !name.isEmpty else { return nil }
            var schema: [String: AnySendableValue] = [:]
            if let rawSchema = raw["inputSchema"] as? [String: Any] {
                schema = AgentToolCall.convert(rawSchema)
            }
            return MCPRemoteTool(
                name: name,
                description: raw["description"] as? String ?? "",
                inputSchema: schema
            )
        }
    }

    /// 把 tools/call 结果的 content 数组拼接为文本：
    /// text 类型直接取 text；其他类型（image/resource 等）序列化为 JSON 保留信息。
    static func renderContent(_ content: Any?) -> String {
        guard let items = content as? [[String: Any]], !items.isEmpty else { return "(empty result)" }
        let parts: [String] = items.map { item in
            if item["type"] as? String == "text", let text = item["text"] as? String {
                return text
            }
            // 非文本内容序列化为 JSON（sortedKeys 输出稳定）
            let data = try? JSONSerialization.data(withJSONObject: item, options: [.sortedKeys])
            return data.flatMap { String(data: $0, encoding: .utf8) } ?? "(unrenderable content)"
        }
        return parts.joined(separator: "\n")
    }
}
