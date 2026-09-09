import Foundation

// MARK: - MCP 客户端配置（Claude Code 风格 mcp.json，纯逻辑可单测）
//
// 配置来源两处，工作区级覆盖全局同名条目：
//   全局：    ~/.meditor/mcp.json
//   工作区：  <工作区>/.meditor/mcp.json
//
// 格式（与 Claude Code 一致）：
//   {"mcpServers": {"<name>": {"command": "...", "args": [...], "env": {...}}}}  —— stdio
//   {"mcpServers": {"<name>": {"url": "https://..."}}}                            —— streamable HTTP
//
// 容错原则：单个坏条目跳过并记录到 issues，不拖垮整个加载。

/// 一个 MCP server 的配置条目。
struct MCPServerConfig: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        /// stdio：启动子进程，JSON-RPC over stdin/stdout（换行分隔消息）
        case stdio(command: String, args: [String], env: [String: String])
        /// streamable HTTP：POST JSON-RPC 到 url
        case http(url: URL)
    }

    var name: String
    var kind: Kind

    /// 设置页展示用的类型标签
    var kindLabel: String {
        switch kind {
        case .stdio: return "stdio"
        case .http:  return "http"
        }
    }
}

/// mcp.json 加载结果：合法条目 + 跳过的坏条目说明（供设置页/日志展示）。
struct MCPClientConfigLoadResult: Sendable {
    var servers: [MCPServerConfig]
    /// 人类可读的容错记录（如 "global: server 'x' has neither 'command' nor 'url'"）。
    /// 文案仅供诊断展示，不做本地化（配置文件本身是英文生态）。
    var issues: [String]
}

enum MCPClientConfigLoader {

    /// 全局配置文件路径（~/.meditor/mcp.json）。
    static var defaultGlobalConfigURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".meditor/mcp.json")
    }

    /// 工作区级配置文件路径（<root>/.meditor/mcp.json）。
    static func workspaceConfigURL(root: URL) -> URL {
        root.appendingPathComponent(".meditor/mcp.json")
    }

    /// 加载并合并全局 + 工作区配置（工作区同名条目覆盖全局）。文件不存在视为空配置。
    static func load(globalConfigURL: URL = defaultGlobalConfigURL,
                     workspaceRoot: URL? = nil) -> MCPClientConfigLoadResult {
        var merged: [String: MCPServerConfig] = [:]
        var order: [String] = []
        var issues: [String] = []

        var sources: [(label: String, url: URL)] = [("global", globalConfigURL)]
        if let workspaceRoot {
            sources.append(("workspace", workspaceConfigURL(root: workspaceRoot)))
        }

        for source in sources {
            guard let data = FileManager.default.contents(atPath: source.url.path) else { continue }
            let parsed = parse(data: data, source: source.label)
            issues.append(contentsOf: parsed.issues)
            for server in parsed.servers {
                if merged[server.name] == nil { order.append(server.name) }
                merged[server.name] = server   // 后加载的（工作区）覆盖同名
            }
        }

        return MCPClientConfigLoadResult(servers: order.compactMap { merged[$0] }, issues: issues)
    }

    /// 解析单个 mcp.json 文件内容。坏条目跳过并记录，不抛错。
    static func parse(data: Data, source: String) -> MCPClientConfigLoadResult {
        var issues: [String] = []

        let obj: Any
        do {
            obj = try JSONSerialization.jsonObject(with: data)
        } catch {
            return MCPClientConfigLoadResult(
                servers: [], issues: ["\(source): invalid JSON (\(error.localizedDescription))"])
        }
        guard let root = obj as? [String: Any] else {
            return MCPClientConfigLoadResult(servers: [], issues: ["\(source): root is not a JSON object"])
        }
        guard let table = root["mcpServers"] as? [String: Any] else {
            if root["mcpServers"] != nil {
                issues.append("\(source): 'mcpServers' is not an object")
            }
            return MCPClientConfigLoadResult(servers: [], issues: issues)
        }

        var servers: [MCPServerConfig] = []
        // 排序保证输出稳定（字典遍历顺序随机），便于测试与日志比对
        for name in table.keys.sorted() {
            guard let entry = table[name] as? [String: Any] else {
                issues.append("\(source): server '\(name)' is not an object — skipped")
                continue
            }
            let parsed = parseEntry(name: name, entry: entry)
            if let config = parsed.config {
                servers.append(config)
            } else if let reason = parsed.issue {
                issues.append("\(source): server '\(name)' \(reason) — skipped")
            }
        }
        return MCPClientConfigLoadResult(servers: servers, issues: issues)
    }

    /// 解析单个 server 条目：stdio（command）或 HTTP（url），两者皆无/皆非法则失败。
    private static func parseEntry(name: String, entry: [String: Any]) -> (config: MCPServerConfig?, issue: String?) {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return (nil, "has an empty name") }

        if let rawURL = entry["url"] {
            guard let urlString = rawURL as? String,
                  let url = URL(string: urlString),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else {
                return (nil, "has an invalid 'url'")
            }
            return (MCPServerConfig(name: trimmedName, kind: .http(url: url)), nil)
        }

        guard let rawCommand = entry["command"] else {
            return (nil, "has neither 'command' nor 'url'")
        }
        guard let command = rawCommand as? String,
              !command.trimmingCharacters(in: .whitespaces).isEmpty else {
            return (nil, "has an empty or non-string 'command'")
        }

        var args: [String] = []
        if let rawArgs = entry["args"] {
            guard let list = rawArgs as? [Any] else {
                return (nil, "'args' is not an array")
            }
            for item in list {
                // 非字符串元素强制字符串化（数字/布尔常见），数组/对象等视为坏条目
                switch item {
                case let s as String:   args.append(s)
                case let n as NSNumber: args.append(n.stringValue)
                default:                return (nil, "'args' contains a non-scalar element")
                }
            }
        }

        var env: [String: String] = [:]
        if let rawEnv = entry["env"] {
            guard let dict = rawEnv as? [String: Any] else {
                return (nil, "'env' is not an object")
            }
            for (key, value) in dict {
                if let s = value as? String { env[key] = s }
                else if let n = value as? NSNumber { env[key] = n.stringValue }
                // 非标量 env 值静默丢弃（不拖垮整个条目）
            }
        }

        return (MCPServerConfig(name: trimmedName, kind: .stdio(command: command, args: args, env: env)), nil)
    }
}
