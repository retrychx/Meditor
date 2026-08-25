import Foundation

// MARK: - MCP JSON-RPC 2.0 编解码（纯逻辑，无 IO，可单测）
//
// MCP stdio 传输约定：newline-delimited JSON（无 Content-Length 头），
// 每条消息独占一行。本文件只负责「一行文本 ↔ 结构化消息」的转换与响应对象构造。

/// JSON-RPC 请求 id：协议允许 string / number / null 三种形态。
enum MCPRequestID: Sendable, Equatable {
    case string(String)
    case int(Int)
    case null

    /// 从 JSONSerialization 解析出的 Any 还原。类型不合法（bool / 数组 / 对象等）返回 nil。
    init?(anyValue: Any?) {
        guard let value = anyValue else { return nil }
        if value is NSNull { self = .null; return }
        if let s = value as? String { self = .string(s); return }
        if let n = value as? NSNumber {
            // Bool 也桥接为 NSNumber；JSON-RPC 的 id 不允许 bool
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return nil }
            self = .int(n.intValue); return
        }
        return nil
    }

    /// 回写 wire format 用的 Foundation 值（.null → NSNull）。
    var anyValue: Any {
        switch self {
        case .string(let s): return s
        case .int(let i):    return i
        case .null:          return NSNull()
        }
    }
}

/// 一条已解析的 JSON-RPC 消息（请求或通知；id 为 nil 表示通知，不应回包）。
struct MCPMessage: Sendable {
    var id: MCPRequestID?
    var method: String
    var params: [String: AnySendableValue]
}

/// 解析 / 协议层错误（code + message，可直接组装成 JSON-RPC error 响应）。
struct MCPError: Sendable, Equatable, Error {
    var code: Int
    var message: String
}

enum MCPJSONRPC {
    static let parseErrorCode     = -32700
    static let invalidRequestCode = -32600
    static let methodNotFoundCode = -32601
    static let invalidParamsCode  = -32602
    static let internalErrorCode  = -32603

    /// 解析一行 stdio 输入。失败时返回错误（此时 id 不可知，响应 id 固定为 null）。
    static func parse(line: String) -> Result<MCPMessage, MCPError> {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) else {
            return .failure(MCPError(code: parseErrorCode, message: "Parse error: invalid JSON"))
        }
        guard let dict = obj as? [String: Any] else {
            return .failure(MCPError(code: invalidRequestCode, message: "Invalid Request: not a JSON object"))
        }
        guard let method = dict["method"] as? String, !method.isEmpty else {
            return .failure(MCPError(code: invalidRequestCode, message: "Invalid Request: missing method"))
        }
        var params: [String: AnySendableValue] = [:]
        if let p = dict["params"] as? [String: Any] {
            params = AgentToolCall.convert(p)
        }
        // id 缺失 → 通知；id 存在但类型非法 → invalid request
        var id: MCPRequestID?
        if let rawID = dict["id"] {
            guard let parsed = MCPRequestID(anyValue: rawID) else {
                return .failure(MCPError(code: invalidRequestCode, message: "Invalid Request: unsupported id type"))
            }
            id = parsed
        }
        return .success(MCPMessage(id: id, method: method, params: params))
    }

    /// 序列化响应对象为单行 JSON（sortedKeys 保证输出稳定，便于测试与日志比对）。
    static func serialize(_ object: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let s = String(data: data, encoding: .utf8) else {
            return #"{"error":{"code":-32603,"message":"Internal error: serialization failed"},"id":null,"jsonrpc":"2.0"}"#
        }
        return s
    }

    static func resultObject(id: MCPRequestID, result: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id.anyValue, "result": result]
    }

    static func errorObject(id: MCPRequestID?, code: Int, message: String) -> [String: Any] {
        [
            "jsonrpc": "2.0",
            "id": (id ?? .null).anyValue,
            "error": ["code": code, "message": message] as [String: Any],
        ]
    }
}

// MARK: - stderr 日志

/// MCP stdio 会话的日志出口：stdout 只写协议消息，诊断信息一律走 stderr。
enum MCPLog {
    static func info(_ message: String) {
        FileHandle.standardError.write(Data("[MEditor MCP] \(message)\n".utf8))
    }
}
