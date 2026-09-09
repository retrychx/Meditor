import Foundation

// MARK: - MCPTool（把远端 MCP 工具包装为 AgentTool，纳入内置 agent 的工具目录）
//
// 命名：mcp__<server>__<tool>（server/tool 名清洗为 [a-zA-Z0-9_-]），与 Claude Code 一致。
// 安全确认：与 RunCommandTool 同一条链路（isCommandApproved / confirmCommandExecution /
// markCommandApproved）——每个 server 每个会话首次调用前向用户确认一次，
// 批准缓存 key 为 "mcp:<server>"，会话内后续调用不再弹框。

struct MCPTool: AgentTool {

    /// 注册名前缀（Runner / 停滞检测 / 日志据此可识别 MCP 工具）
    static let namePrefix = "mcp__"
    /// 命令审批缓存的 key 前缀（与 RunCommandTool 的 per-command-key 缓存共用存储）
    static let approvalKeyPrefix = "mcp:"

    /// 原始 server 名（确认提示用，不清洗——展示给用户看的）
    let serverName: String
    /// 远端工具原名（tools/call 时回传）
    let remoteToolName: String
    /// 所属 server 的客户端会话（actor，天然 Sendable）
    let client: MCPClient
    let spec: AgentToolSpec

    /// - Parameter registeredName: 已查重后的完整注册名（由 MCPClientManager 分配，
    ///   保证全局唯一）；测试可直接用 `Self.registeredName(server:tool:)`。
    init(registeredName: String, serverName: String, remote: MCPRemoteTool, client: MCPClient) {
        self.serverName = serverName
        self.remoteToolName = remote.name
        self.client = client
        self.spec = AgentToolSpec(
            name: registeredName,
            description: remote.description.isEmpty
                ? "MCP tool '\(remote.name)' from server '\(serverName)'"
                : remote.description,
            parameters: Self.fallbackParameters(from: remote.inputSchema),
            rawSchema: remote.inputSchema.isEmpty ? nil : remote.inputSchema
        )
    }

    // MARK: - 命名

    /// 组装注册名：mcp__<server>__<tool>，两个分量各自清洗。
    /// 不含查重——冲突由 MCPClientManager 分配时解决。
    static func registeredName(server: String, tool: String) -> String {
        let name = "\(namePrefix)\(sanitize(server))__\(sanitize(tool))"
        // OpenAI function name 上限 64 字符，超长截断（查重阶段再保证唯一）
        return name.count > 64 ? String(name.prefix(64)) : name
    }

    /// 清洗为 [a-zA-Z0-9_-]：其余字符替换为 "_"（连续折叠），首尾 "_" 去掉；
    /// 清洗后为空（如纯中文名）回退 "x"，保证注册名非空。
    static func sanitize(_ raw: String) -> String {
        var result = ""
        var lastWasUnderscore = false
        for scalar in raw.unicodeScalars {
            let ok = (scalar >= "a" && scalar <= "z") || (scalar >= "A" && scalar <= "Z")
                || (scalar >= "0" && scalar <= "9") || scalar == "-" || scalar == "_"
            if ok {
                result.append(Character(scalar))
                lastWasUnderscore = false
            } else if !lastWasUnderscore {
                result.append("_")
                lastWasUnderscore = true
            }
        }
        let trimmed = result.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return trimmed.isEmpty ? "x" : trimmed
    }

    // MARK: - Spec 降级表示

    /// 从远端 inputSchema 提取顶层属性，转成 ToolParameterSchema——
    /// 供 compactCLIDescription 等展示路径使用；wire 序列化走 rawSchema 原文透传。
    /// 嵌套结构（array items / 嵌套 object）在此降级为类型名，不影响 wire 保真度。
    static func fallbackParameters(from inputSchema: [String: AnySendableValue]) -> ToolParameterSchema {
        var properties: [(key: String, schema: ToolPropertySchema)] = []
        if case .dict(let props)? = inputSchema["properties"] {
            for key in props.keys.sorted() {
                guard case .dict(let p) = props[key] else { continue }
                var enumValues: [String]? = nil
                if case .array(let rawEnum)? = p["enum"] {
                    enumValues = rawEnum.compactMap { $0.stringValue }
                }
                properties.append((key: key, schema: ToolPropertySchema(
                    type: p["type"]?.stringValue ?? "string",
                    description: p["description"]?.stringValue ?? "",
                    enumValues: enumValues
                )))
            }
        }
        var required: [String] = []
        if case .array(let rawRequired)? = inputSchema["required"] {
            required = rawRequired.compactMap { $0.stringValue }
        }
        return ToolParameterSchema(properties: properties, required: required)
    }

    // MARK: - Execute

    func execute(arguments: [String: AnySendableValue], context: any AgentContextProtocol) async throws -> String {
        // 用户确认：每个 server 每个会话首次调用前确认一次（与 RunCommandTool 同一链路）
        let approvalKey = "\(Self.approvalKeyPrefix)\(serverName)"
        if !(await context.isCommandApproved(approvalKey)) {
            let approved = await context.confirmCommandExecution(
                "MCP server \"\(serverName)\" → tool \"\(remoteToolName)\"", cwd: nil)
            guard approved else {
                return "[!] 用户已拒绝调用 MCP server \"\(serverName)\" 的工具"
            }
            await context.markCommandApproved(approvalKey)
        }
        // 还原为 JSON 安全的 Foundation 值，作为 tools/call 的 arguments
        let args = arguments.reduce(into: [String: Any]()) { $0[$1.key] = $1.value.anyValue }
        return try await client.callTool(name: remoteToolName, arguments: args)
    }
}
