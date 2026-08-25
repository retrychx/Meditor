import Foundation

// MARK: - MCP 工具编目（Agent 工具 → MCP 协议的桥接层）

/// 负责两件事：
/// 1. 从 BuiltinAgentTools 全量工具中筛选出适合无头（headless）环境的子集；
/// 2. 把 AgentToolSpec 转成 MCP tools/list 的 wire 格式。
///
/// 工具的 name / description / 参数 schema 一律复用现有 AgentToolSpec 定义生成，
/// 不在此处维护第二份描述，避免两处漂移。
enum MCPToolCatalog {

    /// 依赖 UI / AppState 状态的工具，无头模式下没有语义，不暴露：
    /// - insert_at_cursor：需要编辑器光标位置（无头没有编辑器）；
    /// - open_file：语义是「在编辑器里打开 tab」（退化为读文件，read_file 已覆盖）。
    static let excludedToolNames: Set<String> = [
        "insert_at_cursor",
        "open_file",
    ]

    /// 无头模式暴露的工具集（从全量内建工具实时筛选，注册表增删工具时自动跟随）。
    static var headlessTools: [any AgentTool] {
        BuiltinAgentTools.all.filter { !excludedToolNames.contains($0.spec.name) }
    }

    /// MCP tools/list 的单个工具条目；inputSchema 由 AgentToolSpec 的参数定义生成。
    static func listEntry(for spec: AgentToolSpec) -> [String: Any] {
        var props: [String: Any] = [:]
        for (key, schema) in spec.parameters.orderedProperties {
            var p: [String: Any] = ["type": schema.type, "description": schema.description]
            if let enums = schema.enumValues { p["enum"] = enums }
            props[key] = p
        }
        return [
            "name": spec.name,
            "description": spec.description,
            "inputSchema": [
                "type": "object",
                "properties": props,
                "required": spec.parameters.required,
            ] as [String: Any],
        ]
    }

    /// tools/list 响应的 result 体。
    static func toolsListResult(tools: [any AgentTool]) -> [String: Any] {
        ["tools": tools.map { listEntry(for: $0.spec) }]
    }
}
