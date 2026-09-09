import Foundation
import Observation

// MARK: - MCPClientManager（App 会话级单例，挂在 AppState 上）
//
// 职责：
//   - 加载/合并 mcp.json（全局 + 工作区）
//   - 懒连接：agent run 开始时才连接有配置的 server（refreshForAgentRun）
//   - 降级：连接失败的 server 跳过并记录，不阻塞整个 run；
//     modelFacingNotice 把失败名单注入系统提示，让模型知道哪些工具不可用
//   - 向设置页暴露连接状态（statuses）

@MainActor
@Observable
final class MCPClientManager {

    /// 单个 server 的连接状态（设置页展示）
    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected(tools: Int)
        case failed(String)
    }

    struct ServerStatus: Equatable, Identifiable {
        var id: String { name }
        let name: String
        let kindLabel: String   // "stdio" / "http"
        var state: ConnectionState
    }

    /// 当前已配置 server 的状态列表（设置页数据源）
    private(set) var statuses: [ServerStatus] = []
    /// 配置解析容错记录（坏条目说明）
    private(set) var configIssues: [String] = []

    /// server 名 → 已连接的客户端（未连接/失败的 server 不在内）
    private var clients: [String: MCPClient] = [:]
    /// server 名 → 上次加载的配置（用于判断配置变更需要重连）
    private var configs: [String: MCPServerConfig] = [:]
    /// 防止并发 refresh 重复连接（run 开始与设置页重连可能撞车）
    private var refreshTask: Task<[any AgentTool], Never>?

    // MARK: - 配置加载（设置页展示用，不发起连接）

    /// 仅重载配置与状态列表（设置页打开时调用，避免设置页一打开就拉起一堆子进程）。
    func reloadConfigSummaries(workspaceURL: URL?,
                               globalConfigURL: URL = MCPClientConfigLoader.defaultGlobalConfigURL) {
        let result = MCPClientConfigLoader.load(globalConfigURL: globalConfigURL, workspaceRoot: workspaceURL)
        configIssues = result.issues
        configs = Dictionary(uniqueKeysWithValues: result.servers.map { ($0.name, $0) })
        statuses = result.servers.map { config in
            // 已有连接状态的保留（reload 不断开现有连接）
            if let existing = statuses.first(where: { $0.name == config.name }),
               clients[config.name] != nil {
                return ServerStatus(name: config.name, kindLabel: config.kindLabel, state: existing.state)
            }
            return ServerStatus(name: config.name, kindLabel: config.kindLabel, state: .disconnected)
        }
    }

    // MARK: - Agent run 懒连接

    /// run 开始时的入口：加载配置 → 关掉配置已变更/已移除的连接 → 并发连接新 server →
    /// 汇总全部可用 MCP 工具。失败的 server 降级为跳过（记入 statuses 与 modelFacingNotice）。
    /// 并发安全：进行中的 refresh 会被后来的调用复用，不会重复连接。
    func refreshForAgentRun(
        workspaceURL: URL?,
        globalConfigURL: URL = MCPClientConfigLoader.defaultGlobalConfigURL
    ) async -> [any AgentTool] {
        if let inFlight = refreshTask { return await inFlight.value }
        let task = Task { await self.performRefresh(workspaceURL: workspaceURL, globalConfigURL: globalConfigURL) }
        refreshTask = task
        let tools = await task.value
        refreshTask = nil
        return tools
    }

    /// 设置页「重新连接」：等进行中的 refresh 落定后断开全部连接，再重新走一遍 refresh。
    func reconnectAll(workspaceURL: URL?) async {
        if let inFlight = refreshTask { _ = await inFlight.value }
        for (_, client) in clients { await client.close() }
        clients.removeAll()
        refreshTask = nil
        _ = await refreshForAgentRun(workspaceURL: workspaceURL)
    }

    private func performRefresh(workspaceURL: URL?, globalConfigURL: URL) async -> [any AgentTool] {
        let result = MCPClientConfigLoader.load(globalConfigURL: globalConfigURL, workspaceRoot: workspaceURL)
        configIssues = result.issues
        let newConfigs = Dictionary(uniqueKeysWithValues: result.servers.map { ($0.name, $0) })

        // 关闭配置已变更或已移除的 server 连接
        for (name, client) in clients where newConfigs[name] != configs[name] {
            await client.close()
            clients.removeValue(forKey: name)
        }
        configs = newConfigs

        // 初始化状态列表（已连接的保留状态）
        statuses = result.servers.map { config in
            let state: ConnectionState = clients[config.name] != nil
                ? (statuses.first(where: { $0.name == config.name })?.state ?? .disconnected)
                : .disconnected
            return ServerStatus(name: config.name, kindLabel: config.kindLabel, state: state)
        }

        // 并发连接尚未连接的 server；每个 server 的失败互不影响
        let toConnect = result.servers.filter { clients[$0.name] == nil }
        for config in toConnect { setState(.connecting, for: config.name) }
        await withTaskGroup(of: (String, Result<MCPClient, Error>).self) { group in
            for config in toConnect {
                group.addTask {
                    let client = MCPClient(config: config)
                    do {
                        try await client.connect()
                        return (config.name, .success(client))
                    } catch {
                        return (config.name, .failure(error))
                    }
                }
            }
            for await (name, outcome) in group {
                switch outcome {
                case .success(let client):
                    clients[name] = client
                    setState(.connected(tools: await client.tools.count), for: name)
                case .failure(let error):
                    setState(.failed(error.localizedDescription), for: name)
                }
            }
        }

        // 汇总可用工具（按 server 名排序，注册名查重后分配）
        var tools: [any AgentTool] = []
        var usedNames = Set(BuiltinAgentTools.all.map { $0.spec.name })
        for name in configs.keys.sorted() {
            guard let client = clients[name] else { continue }
            for remote in await client.tools {
                var registered = MCPTool.registeredName(server: name, tool: remote.name)
                var suffix = 2
                // 同名冲突（清洗后重名 / 与内建工具重名）：追加数字后缀，保证注册名唯一
                while usedNames.contains(registered) {
                    let tail = "_\(suffix)"
                    registered = String(MCPTool.registeredName(server: name, tool: remote.name)
                        .prefix(64 - tail.count)) + tail
                    suffix += 1
                }
                usedNames.insert(registered)
                tools.append(MCPTool(registeredName: registered, serverName: name, remote: remote, client: client))
            }
        }
        return tools
    }

    /// 给模型看的提示：连接失败的 server 名单（这些 mcp__ 工具本轮不可用）。
    /// 英文：系统提示整体是英文语境。nil = 无失败。
    var modelFacingNotice: String? {
        let failed = statuses.compactMap { status -> String? in
            if case .failed = status.state { return status.name }
            return nil
        }
        guard !failed.isEmpty else { return nil }
        return "\n\nNote: MCP server(s) \(failed.joined(separator: ", ")) failed to connect; "
            + "their tools are unavailable in this run. Do not attempt to call mcp__ tools for them."
    }

    private func setState(_ state: ConnectionState, for name: String) {
        guard let index = statuses.firstIndex(where: { $0.name == name }) else { return }
        statuses[index].state = state
    }
}
