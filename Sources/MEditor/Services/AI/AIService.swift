import Foundation

// MARK: - Provider kind

enum AIProviderKind: String, CaseIterable, Identifiable, Sendable {
    case disabled
    case openai      // OpenAI-compatible /chat/completions (OpenAI, Ollama, LM Studio, vLLM, gateways…)
    case claudeCLI   // local `claude` CLI subprocess (reuses existing Claude Code auth)

    var id: String { rawValue }

    var labelKey: String {
        switch self {
        case .disabled:  return "ai.provider.disabled"
        case .openai:    return "ai.provider.openai"
        case .claudeCLI: return "ai.provider.claudeCLI"
        }
    }
}

// MARK: - Provider presets

/// Common OpenAI-compatible vendors with their base URL and a handful of
/// commonly-used model names (best-effort; "Refresh" fetches the live list).
struct AIProviderPreset: Identifiable {
    let id: String
    let name: String
    let baseURL: String
    let models: [String]
}

enum AIPresets {
    static let all: [AIProviderPreset] = [
        .init(id: "openai", name: "OpenAI", baseURL: "https://api.openai.com/v1",
              models: ["gpt-4o", "gpt-4o-mini", "gpt-4.1", "gpt-4.1-mini", "o3", "o3-mini", "o1"]),
        .init(id: "deepseek", name: "DeepSeek", baseURL: "https://api.deepseek.com/v1",
              models: ["deepseek-chat", "deepseek-reasoner"]),
        .init(id: "moonshot", name: "Moonshot · Kimi", baseURL: "https://api.moonshot.cn/v1",
              models: ["kimi-k2-0711-preview", "moonshot-v1-8k", "moonshot-v1-32k", "moonshot-v1-128k"]),
        .init(id: "zhipu", name: "智谱 · GLM", baseURL: "https://open.bigmodel.cn/api/paas/v4",
              models: ["glm-4.6", "glm-4-plus", "glm-4-air", "glm-4-flash"]),
        .init(id: "qwen", name: "通义千问 · DashScope", baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
              models: ["qwen-max", "qwen-plus", "qwen-turbo", "qwen2.5-72b-instruct"]),
        .init(id: "openrouter", name: "OpenRouter", baseURL: "https://openrouter.ai/api/v1",
              models: ["openai/gpt-4o", "anthropic/claude-3.7-sonnet", "google/gemini-2.0-flash-001", "deepseek/deepseek-chat"]),
        .init(id: "groq", name: "Groq", baseURL: "https://api.groq.com/openai/v1",
              models: ["llama-3.3-70b-versatile", "llama-3.1-8b-instant", "mixtral-8x7b-32768"]),
        .init(id: "ollama", name: "Ollama · 本地", baseURL: "http://localhost:11434/v1",
              models: ["llama3.1", "qwen2.5", "mistral", "gemma2", "phi3"])
    ]

    /// Preset whose base URL matches the given one, if any.
    static func match(_ baseURL: String) -> AIProviderPreset? {
        let b = baseURL.trimmingCharacters(in: .whitespaces)
        return all.first { $0.baseURL == b }
    }
}

// MARK: - Message
struct AIMessage: Sendable {
    enum Role: String, Sendable { case system, user, assistant }
    let role: Role
    let content: String
}

// MARK: - Errors

enum AIError: LocalizedError {
    case notConfigured
    case badURL
    case server(Int, String)
    case cliNotFound(String)
    case cliFailed(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:        return L("ai.error.notConfigured")
        case .badURL:               return L("ai.error.badURL")
        case .server(let c, let m): return L("ai.error.server", c, m)
        case .cliNotFound(let p):   return L("ai.error.cliNotFound", p)
        case .cliFailed(let m):     return L("ai.error.cliFailed", m)
        case .network(let m):       return L("ai.error.network", m)
        }
    }
}

// MARK: - Config

/// 使用 AI 的场景，决定选哪个模型。
enum AIScene {
    case chat       // AI 助手面板（流式聊天）
    case agent      // AgentRunner（工具调用）
    case inline     // 内联编辑（改写/精简/翻译）
    case beautify   // HTML 美化
}

struct AIConfig: Sendable {
    var kind: AIProviderKind
    var baseURL: String
    var model: String
    var cliPath: String
    var cliModel: String    // Claude CLI --model 参数（空则用 CLI 默认）
    var apiKey: String      // resolved from Keychain

    @MainActor
    static func current(_ s: AppSettings, scene: AIScene = .chat) -> AIConfig {
        // 根据场景决定模型
        let model: String
        switch scene {
        case .agent:
            model = s.aiAgentModel.trimmingCharacters(in: .whitespaces).isEmpty
                ? s.aiModel.trimmingCharacters(in: .whitespaces)
                : s.aiAgentModel.trimmingCharacters(in: .whitespaces)
        case .inline:
            model = s.aiInlineModel.trimmingCharacters(in: .whitespaces).isEmpty
                ? s.aiModel.trimmingCharacters(in: .whitespaces)
                : s.aiInlineModel.trimmingCharacters(in: .whitespaces)
        default:
            model = s.aiModel.trimmingCharacters(in: .whitespaces)
        }
        return AIConfig(
            kind:     AIProviderKind(rawValue: s.aiProvider) ?? .disabled,
            baseURL:  s.aiBaseURL.trimmingCharacters(in: .whitespaces),
            model:    model,
            cliPath:  s.aiCLIPath.trimmingCharacters(in: .whitespaces),
            cliModel: s.aiCLIModel.trimmingCharacters(in: .whitespaces),
            apiKey:   AIKeychain.load() ?? ""
        )
    }

    var isConfigured: Bool {
        switch kind {
        case .disabled:  return false
        case .openai:    return !baseURL.isEmpty && !model.isEmpty
        case .claudeCLI: return !cliPath.isEmpty
        }
    }
}

// MARK: - Keychain (API key)

/// API Key 存储。
/// 使用 UserDefaults 而非 Keychain，原因：
///   - Keychain ACL 绑定 code signature，每次 cp 替换二进制都会弹授权窗口
///   - API Key 已通过 HTTPS 传输，本地明文存储与 Keychain 安全级别差异可接受
///   - 彻底消除开发期反复弹窗的摩擦
enum AIKeychain {
    private static let key = "meditor.ai.apiKey"

    static func save(_ value: String) {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if v.isEmpty { UserDefaults.standard.removeObject(forKey: key) }
        else { UserDefaults.standard.set(v, forKey: key) }
    }

    static func load() -> String? {
        let v = UserDefaults.standard.string(forKey: key) ?? ""
        return v.isEmpty ? nil : v
    }

    static func clear() { UserDefaults.standard.removeObject(forKey: key) }
    static var hasKey: Bool { load() != nil }
}

// MARK: - Client

/// Stateless streaming client. `stream(_:)` yields response text chunks as they
/// arrive. Runs entirely off the main actor.
struct AIClient {
    let config: AIConfig

    func stream(_ messages: [AIMessage]) -> AsyncThrowingStream<String, Error> {
        switch config.kind {
        case .disabled:  return previewStream()
        case .openai:    return openAIStream(messages)
        case .claudeCLI: return claudeCLIStream(messages)
        }
    }

    /// Convenience Task-wrapper around `stream()`.
    /// Buffers chunks at ≥ 50 ms intervals, then calls `onChunk` on MainActor.
    /// Fires `onComplete` exactly once with the full text or error.
    @MainActor
    func streamTask(
        _ messages: [AIMessage],
        onChunk: @escaping @MainActor (String) -> Void,
        onComplete: @escaping @MainActor (String?, Error?) -> Void
    ) -> Task<Void, Never> {
        Task { @MainActor in
            var accumulated = ""
            var buffer      = ""
            var lastFlush   = Date.distantPast
            do {
                for try await chunk in stream(messages) {
                    try Task.checkCancellation()
                    buffer += chunk
                    if Date().timeIntervalSince(lastFlush) > 0.05 {
                        accumulated += buffer
                        onChunk(buffer)
                        buffer    = ""
                        lastFlush = Date()
                    }
                }
                if !buffer.isEmpty {
                    accumulated += buffer
                    onChunk(buffer)
                }
                onComplete(accumulated, nil)
            } catch is CancellationError {
                onComplete(accumulated.isEmpty ? nil : accumulated, nil)
            } catch {
                onComplete(accumulated.isEmpty ? nil : accumulated, error)
            }
        }
    }

    // MARK: Offline preview

    private func previewStream() -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(L("ai.previewReply"))
            continuation.finish()
        }
    }

    // MARK: OpenAI-compatible SSE

    private func openAIStream(_ messages: [AIMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard config.isConfigured else { throw AIError.notConfigured }
                    let endpoint = config.baseURL.hasSuffix("/")
                        ? config.baseURL + "chat/completions"
                        : config.baseURL + "/chat/completions"
                    guard let url = URL(string: endpoint) else { throw AIError.badURL }

                    var req = URLRequest(url: url)
                    req.httpMethod = "POST"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    if !config.apiKey.isEmpty {
                        req.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
                    }
                    // Fail fast if the endpoint never responds (the byte stream
                    // itself stays open for the whole generation once flowing).
                    req.timeoutInterval = 60

                    let payload: [String: Any] = [
                        "model": config.model,
                        "stream": true,
                        "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] }
                    ]
                    req.httpBody = try JSONSerialization.data(withJSONObject: payload)

                    let session = URLSession(configuration: {
                        let c = URLSessionConfiguration.default
                        c.timeoutIntervalForRequest = 60          // idle timeout between bytes
                        c.timeoutIntervalForResource = 600         // overall ceiling
                        c.waitsForConnectivity = false
                        return c
                    }())

                    let (bytes, response) = try await session.bytes(for: req)
                    guard let http = response as? HTTPURLResponse else {
                        throw AIError.network("invalid response")
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        var body = ""
                        for try await line in bytes.lines { body += line; if body.count > 500 { break } }
                        throw AIError.server(http.statusCode, body)
                    }

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        if let chunk = Self.decodeDelta(payload) { continuation.yield(chunk) }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch let e as AIError {
                    continuation.finish(throwing: e)
                } catch {
                    continuation.finish(throwing: AIError.network(error.localizedDescription))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Extracts `choices[0].delta.content` from one SSE JSON payload.
    private static func decodeDelta(_ payload: String) -> String? {
        guard let data = payload.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let first = choices.first else { return nil }
        if let delta = first["delta"] as? [String: Any],
           let content = delta["content"] as? String { return content }
        // Some servers send the full message on the final frame.
        if let message = first["message"] as? [String: Any],
           let content = message["content"] as? String { return content }
        return nil
    }

    // MARK: Local Claude CLI

    private func claudeCLIStream(_ messages: [AIMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            // Box lets the termination closure reach the process after it starts.
            final class ProcessBox { var process: Process? }
            let box = ProcessBox()

            let task = Task.detached {
                do {
                    guard !config.cliPath.isEmpty else { throw AIError.notConfigured }
                    guard FileManager.default.isExecutableFile(atPath: config.cliPath) else {
                        throw AIError.cliNotFound(config.cliPath)
                    }

                    // Compose a single prompt: system context + conversation.
                    let prompt = messages.map { m -> String in
                        switch m.role {
                        case .system:    return m.content
                        case .user:      return "User: \(m.content)"
                        case .assistant: return "Assistant: \(m.content)"
                        }
                    }.joined(separator: "\n\n")

                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: config.cliPath)
                    // `-p` = print mode (non-interactive). The prompt is fed via
                    // stdin (not argv) so content starting with "-"/"---" isn't
                    // mis-parsed as a CLI option.
                    process.arguments = ["-p"]

                    // GUI 应用不继承 shell 环境，需要从 login shell 读取关键变量
                    // （包括 ANTHROPIC_BASE_URL 等自定义代理地址）
                    var env = ProcessInfo.processInfo.environment
                    let home = FileManager.default.homeDirectoryForCurrentUser.path

                    // 从 login shell 读取完整环境（包含 .zshrc/.bashrc 里的配置）
                    if let shellEnv = Self.loginShellEnvironment() {
                        for (key, value) in shellEnv {
                            env[key] = value
                        }
                    }

                    // 额外补充常见安装路径
                    let extra = [
                        "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin",
                        "\(home)/.local/bin", "\(home)/.bun/bin",
                        "\(home)/.npm-global/bin", "\(home)/.volta/bin",
                        "\(home)/.nvm/current/bin"
                    ]
                    let current = env["PATH"] ?? ""
                    env["PATH"] = (extra + (current.isEmpty ? [] : [current])).joined(separator: ":")
                    process.environment = env

                    let outPipe = Pipe()
                    let errPipe = Pipe()
                    let inPipe = Pipe()
                    process.standardOutput = outPipe
                    process.standardError = errPipe
                    process.standardInput = inPipe

                    try Task.checkCancellation()
                    try process.run()
                    box.process = process

                    // Feed the prompt via stdin, then close it so the CLI proceeds.
                    if let data = prompt.data(using: .utf8) {
                        inPipe.fileHandleForWriting.write(data)
                    }
                    try? inPipe.fileHandleForWriting.close()

                    // `claude -p` writes the complete reply then exits — block until
                    // EOF. `availableData` is non-blocking and exits early if the
                    // subprocess hasn't flushed yet, so we use readDataToEndOfFile().
                    // The termination closure calls process.terminate() which closes
                    // the pipe and unblocks this call when the Task is cancelled.
                    let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()

                    if Task.isCancelled { continuation.finish(); return }

                    if process.terminationStatus != 0 {
                        let msg = String(data: errData, encoding: .utf8) ?? "exit \(process.terminationStatus)"
                        throw AIError.cliFailed(msg.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                    if let output = String(data: outData, encoding: .utf8), !output.isEmpty {
                        continuation.yield(output)
                    }
                    continuation.finish()
                } catch let e as AIError {
                    continuation.finish(throwing: e)
                } catch {
                    continuation.finish(throwing: AIError.cliFailed(error.localizedDescription))
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
                box.process?.terminate()
            }
        }
    }
}

// MARK: - Login shell environment

extension AIClient {
    /// 通过 login shell 获取用户完整环境变量。
    /// GUI 应用不继承 .zshrc/.profile，主要用于读取
    /// ANTHROPIC_BASE_URL、ANTHROPIC_AUTH_TOKEN 等自定义代理配置。
    ///
    /// 结果在进程生命周期内只采集一次（shell 环境在运行时不会改变），
    /// 后续调用直接返回缓存，避免每次 AI 对话都 spawn 子进程。
    static func loginShellEnvironment() -> [String: String]? {
        // nonisolated(unsafe)：只写一次，后续只读；最多在首次并发时多
        // spawn 一次 shell，结果幂等，可接受。
        if let cached = _cachedShellEnv { return cached }
        let env = _collectShellEnvironment()
        _cachedShellEnv = env
        return env
    }

    // MARK: Private

    /// 进程级缓存，避免重复 spawn login shell。
    nonisolated(unsafe) private static var _cachedShellEnv: [String: String]? = nil

    private static func _collectShellEnvironment() -> [String: String]? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: shell)
        p.arguments = ["-l", "-c", "env"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()   // 丢弃 stderr
        guard (try? p.run()) != nil else { return nil }
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        var result: [String: String] = [:]
        for line in text.components(separatedBy: "\n") {
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[line.startIndex ..< eq])
            let value = String(line[line.index(after: eq)...])
            result[key] = value
        }
        return result.isEmpty ? nil : result
    }
}

// MARK: - Discovery helpers

extension AIClient {

    /// Fetches available model IDs from an OpenAI-compatible `/models` endpoint.
    /// Returns an empty array on any failure (caller falls back to manual entry).
    static func fetchModels(baseURL: String, apiKey: String) async -> [String] {
        let base = baseURL.trimmingCharacters(in: .whitespaces)
        guard !base.isEmpty else { return [] }
        let endpoint = base.hasSuffix("/") ? base + "models" : base + "/models"
        guard let url = URL(string: endpoint) else { return [] }

        var req = URLRequest(url: url)
        if !apiKey.isEmpty {
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let arr = obj["data"] as? [[String: Any]] else { return [] }
            return arr.compactMap { $0["id"] as? String }.sorted()
        } catch {
            return []
        }
    }

    /// Best-effort detection of the local `claude` CLI: a login shell lookup
    /// first, then a scan of common install locations. Returns an absolute path.
    static func detectClaudeCLI() async -> String? {
        if let p = await loginShellWhich("claude"),
           FileManager.default.isExecutableFile(atPath: p) {
            return p
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "\(home)/.bun/bin/claude",
            "\(home)/.npm-global/bin/claude",
            "\(home)/.volta/bin/claude"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func loginShellWhich(_ tool: String) async -> String? {
        await withCheckedContinuation { cont in
            DispatchQueue.global().async {
                let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
                let p = Process()
                p.executableURL = URL(fileURLWithPath: shell)
                p.arguments = ["-lc", "command -v \(tool)"]
                let pipe = Pipe()
                p.standardOutput = pipe
                p.standardError = Pipe()
                do { try p.run(); p.waitUntilExit() }
                catch { cont.resume(returning: nil); return }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let out = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                cont.resume(returning: (out?.isEmpty == false) ? out : nil)
            }
        }
    }
}
