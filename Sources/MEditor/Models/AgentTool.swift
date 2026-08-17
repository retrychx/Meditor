import Foundation

// MARK: - Tool Property Schema

struct ToolPropertySchema: Sendable {
    var type: String
    var description: String
    var enumValues: [String]?
}

// MARK: - Tool Parameter Schema（有序 properties，保证传给 AI 的字段顺序稳定）

struct ToolParameterSchema: Sendable {
    var type: String = "object"
    /// 有序键值对，避免 Dictionary 随机顺序影响模型对参数的理解
    var orderedProperties: [(key: String, schema: ToolPropertySchema)]
    var required: [String]

    init(
        type: String = "object",
        properties: [(key: String, schema: ToolPropertySchema)] = [],
        required: [String] = []
    ) {
        self.type = type
        self.orderedProperties = properties
        self.required = required
    }

    /// 便捷初始化：接受 [String: ToolPropertySchema] 并按 key 字母排序（兼容旧调用）
    init(
        type: String = "object",
        properties: [String: ToolPropertySchema],
        required: [String] = []
    ) {
        self.type = type
        self.orderedProperties = properties.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
        self.required = required
    }
}

// MARK: - Agent Tool Spec

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
        for (key, schema) in parameters.orderedProperties {
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

    // Anthropic Messages API tool format
    var anthropicDict: [String: Any] {
        var props: [String: Any] = [:]
        for (key, schema) in parameters.orderedProperties {
            var p: [String: Any] = ["type": schema.type, "description": schema.description]
            if let enums = schema.enumValues { p["enum"] = enums }
            props[key] = p
        }
        return [
            "name": name,
            "description": description,
            "input_schema": [
                "type": "object",
                "properties": props,
                "required": parameters.required
            ] as [String: Any]
        ]
    }

    /// 紧凑单行签名：ClaudeCLI system prompt 专用，比 XML 省 ~70% token。
    /// 格式：`name(param: type, optional?: type)  description`
    var compactCLIDescription: String {
        let params = parameters.orderedProperties.map { (key, schema) -> String in
            let req = parameters.required.contains(key)
            let t: String
            switch schema.type {
            case "string":  t = "str"
            case "boolean": t = "bool"
            case "array":   t = "[str]"
            case "integer", "number": t = "num"
            default:        t = schema.type
            }
            return req ? "\(key): \(t)" : "\(key)?: \(t)"
        }.joined(separator: ", ")
        let sig = params.isEmpty ? name : "\(name)(\(params))"
        return "  \(sig)\n    ↳ \(description)"
    }

    // Claude XML-style tool description
    var claudeXMLDescription: String {
        var lines = ["<tool>", "<name>\(name)</name>", "<description>\(description)</description>"]
        if !parameters.orderedProperties.isEmpty {
            lines.append("<parameters>")
            for (key, schema) in parameters.orderedProperties {
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
// 用强类型 AnySendableValue 替代 [String: Any]，消除 @unchecked Sendable

enum AnySendableValue: Sendable, Codable {
    case string(String)
    case bool(Bool)
    case int(Int)
    case double(Double)
    case array([AnySendableValue])
    case dict([String: AnySendableValue])
    case null

    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }
    var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }
    var intValue: Int? {
        if case .int(let i) = self { return i }
        return nil
    }

    /// 还原为 Foundation `Any`（`.null` → NSNull），供 JSONSerialization 回写 wire format。
    /// 唯一的 unwrap 实现——此前同一份 switch 抄了 3 遍（这里 / AgentBackend / AgentRunner）。
    var anyValue: Any {
        switch self {
        case .string(let s):  return s
        case .bool(let b):    return b
        case .int(let i):     return i
        case .double(let d):  return d
        case .null:           return NSNull()
        case .array(let arr): return arr.map { $0.anyValue }
        case .dict(let d):    return d.reduce(into: [String: Any]()) { $0[$1.key] = $1.value.anyValue }
        }
    }
}

struct AgentToolCall: Sendable {
    var id: String
    var name: String
    var arguments: [String: AnySendableValue]
    /// 后端返回的原始参数 JSON 字符串（用于 wire 回放与错误诊断）
    var rawArgumentsJSON: String? = nil
    /// 参数 JSON 解析失败的错误摘要；非 nil 表示 arguments 为空是解析失败所致，
    /// Runner 应跳过执行并直接回灌错误，避免工具误报「缺少参数」误导模型
    var argumentsParseError: String? = nil

    // Parse arguments from JSON string
    init(id: String, name: String, argumentsJSON: String) {
        self.id = id
        self.name = name
        self.rawArgumentsJSON = argumentsJSON
        if let data = argumentsJSON.data(using: .utf8) {
            do {
                if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    self.arguments = Self.convert(obj)
                } else {
                    self.arguments = [:]
                    self.argumentsParseError = "参数不是 JSON 对象"
                }
            } catch {
                self.arguments = [:]
                self.argumentsParseError = error.localizedDescription
            }
        } else {
            self.arguments = [:]
            self.argumentsParseError = "参数不是有效的 UTF-8 文本"
        }
    }

    /// 将强类型 arguments 还原为 [String: Any]（用于序列化回 wire format）
    var argumentsDict: [String: Any] {
        arguments.reduce(into: [String: Any]()) { $0[$1.key] = $1.value.anyValue }
    }

    init(id: String, name: String, arguments: [String: AnySendableValue] = [:]) {
        self.id = id
        self.name = name
        self.arguments = arguments
        self.rawArgumentsJSON = nil
        self.argumentsParseError = nil
    }

    /// 递归将 [String: Any] 转换为 [String: AnySendableValue]
    static func convert(_ dict: [String: Any]) -> [String: AnySendableValue] {
        var result: [String: AnySendableValue] = [:]
        for (key, value) in dict {
            result[key] = convertValue(value)
        }
        return result
    }

    private static func convertValue(_ value: Any) -> AnySendableValue {
        switch value {
        case let s as String:  return .string(s)
        case let b as Bool:    return .bool(b)
        case let i as Int:     return .int(i)
        case let d as Double:  return .double(d)
        case let arr as [Any]: return .array(arr.map { convertValue($0) })
        case let dict as [String: Any]: return .dict(convert(dict))
        default: return .null
        }
    }
}

// MARK: - AgentToolCall Codable

extension AgentToolCall: Codable {
    enum CodingKeys: String, CodingKey { case id, name, arguments }
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
    func execute(arguments: [String: AnySendableValue], context: any AgentContextProtocol) async throws -> String
}

// MARK: - Agent Runner Step（独立为 Model，不再混入 Runner）

enum AgentRunnerStep: Identifiable, Sendable {
    case thinking(label: String, id: UUID = UUID())
    case toolCall(id: String, name: String, args: String)
    /// durationSeconds：工具实际执行耗时（仅 tool.execute 真实执行的分支有值；
    /// 参数解析失败/未找到工具等短路分支为 nil）。默认 nil，旧构造点不受影响。
    case toolCallDone(id: String, name: String, args: String, result: String, isError: Bool,
                      durationSeconds: TimeInterval? = nil)

    /// SwiftUI 用来标识同一视图的 key。
    /// toolCall 和 toolCallDone 共享同一 id，让 SwiftUI 将它们识别为同一个视图，实现原地内容过渡。
    var id: String {
        switch self {
        case .thinking(_, let uid):                 return uid.uuidString
        case .toolCall(let id, _, _):               return "call-\(id)"
        case .toolCallDone(let id, _, _, _, _, _):  return "call-\(id)"   // 意图与 toolCall 相同
        }
    }

    var isDone:  Bool { if case .toolCallDone = self { return true  }; return false }
    var isError: Bool { if case .toolCallDone(_, _, _, _, let e, _) = self { return e }; return false }
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
        case .noDocument:            return "没有打开的文档"
        case .noWorkspace:           return "没有打开工作区"
        case .toolNotFound(let n):   return "工具未找到：\(n)"
        case .maxStepsExceeded:      return "Agent 执行步数超限"
        case .parseError(let m):     return "解析错误：\(m)"
        case .executionError(let m): return "执行错误：\(m)"
        }
    }
}
