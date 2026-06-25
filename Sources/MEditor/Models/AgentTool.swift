import Foundation

// MARK: - Tool Schema (JSON Schema subset for OpenAI function calling)

struct ToolPropertySchema: Codable, Sendable {
    var type: String
    var description: String
    var enumValues: [String]?

    enum CodingKeys: String, CodingKey {
        case type, description
        case enumValues = "enum"
    }
}

struct ToolParameterSchema: Codable, Sendable {
    var type: String = "object"
    var properties: [String: ToolPropertySchema] = [:]
    var required: [String] = []
}

struct AgentToolSpec: Sendable {
    var name: String
    var description: String
    var parameters: ToolParameterSchema

    init(name: String, description: String, parameters: ToolParameterSchema = ToolParameterSchema()) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }

    // Serialize to OpenAI tool format
    var openAIDict: [String: Any] {
        var props: [String: Any] = [:]
        for (key, schema) in parameters.properties {
            var p: [String: Any] = ["type": schema.type, "description": schema.description]
            if let enums = schema.enumValues { p["enum"] = enums }
            props[key] = p
        }
        return [
            "type": "function",
            "function": [
                "name": name,
                "description": description,
                "parameters": [
                    "type": "object",
                    "properties": props,
                    "required": parameters.required
                ] as [String: Any]
            ] as [String: Any]
        ]
    }

    // Claude XML-style tool description
    var claudeXMLDescription: String {
        var lines = ["<tool>", "<name>\(name)</name>", "<description>\(description)</description>"]
        if !parameters.properties.isEmpty {
            lines.append("<parameters>")
            for (key, schema) in parameters.properties {
                lines.append("  <parameter>")
                lines.append("    <name>\(key)</name>")
                lines.append("    <type>\(schema.type)</type>")
                lines.append("    <description>\(schema.description)</description>")
                if parameters.required.contains(key) {
                    lines.append("    <required>true</required>")
                }
                lines.append("  </parameter>")
            }
            lines.append("</parameters>")
        }
        lines.append("</tool>")
        return lines.joined(separator: "\n")
    }
}

// MARK: - Tool Call (from AI response)

struct AgentToolCall: @unchecked Sendable {
    var id: String
    var name: String
    var arguments: [String: Any]

    // Parse arguments from JSON string
    init(id: String, name: String, argumentsJSON: String) {
        self.id = id
        self.name = name
        if let data = argumentsJSON.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            self.arguments = obj
        } else {
            self.arguments = [:]
        }
    }

    init(id: String, name: String, arguments: [String: Any] = [:]) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

// MARK: - Tool Result

struct AgentToolResult: Sendable {
    var toolCallID: String
    var toolName: String
    var content: String
    var isError: Bool

    init(toolCallID: String, toolName: String, content: String, isError: Bool = false) {
        self.toolCallID = toolCallID
        self.toolName = toolName
        self.content = content
        self.isError = isError
    }
}

// MARK: - Agent Tool Protocol

protocol AgentTool: Sendable {
    var spec: AgentToolSpec { get }
    func execute(arguments: [String: Any], context: AgentContext) async throws -> String
}

// MARK: - Agent Step (for UI display)

enum AgentStep: Identifiable {
    case thinking
    case toolCall(name: String, args: String)
    case toolResult(name: String, content: String, isError: Bool)
    case text(String)

    var id: String {
        switch self {
        case .thinking:                         return "thinking"
        case .toolCall(let n, _):               return "call-\(n)-\(UUID().uuidString)"
        case .toolResult(let n, _, _):          return "result-\(n)-\(UUID().uuidString)"
        case .text(let t):                      return "text-\(t.prefix(20))"
        }
    }
}

// MARK: - Errors

enum AgentError: LocalizedError {
    case noDocument
    case noWorkspace
    case toolNotFound(String)
    case maxStepsExceeded
    case parseError(String)
    case executionError(String)

    var errorDescription: String? {
        switch self {
        case .noDocument:           return "没有打开的文档"
        case .noWorkspace:          return "没有打开工作区"
        case .toolNotFound(let n):  return "工具未找到：\(n)"
        case .maxStepsExceeded:     return "Agent 执行步数超限"
        case .parseError(let m):    return "解析错误：\(m)"
        case .executionError(let m):return "执行错误：\(m)"
        }
    }
}
