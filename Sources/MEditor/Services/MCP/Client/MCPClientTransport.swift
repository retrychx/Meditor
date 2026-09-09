import Foundation

// MARK: - MCP 客户端传输层
//
// MCPClientTransport        —— 传输协议（request / notify / close）
// MCPStdioTransport         —— 子进程 stdio（换行分隔 JSON-RPC，仅 macOS）
// MCPStreamableHTTPTransport —— streamable HTTP（POST JSON-RPC；SSE 响应简化为读完整 body）
//
// 与服务端（MCPServer）的约定一致：无 Content-Length 头，一条消息一行。

/// 传输层错误。文案面向日志/设置页诊断，不做本地化。
enum MCPTransportError: LocalizedError {
    case closed
    case timeout(method: String, seconds: Int)
    case processExited(stderr: String)
    case httpStatus(Int)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .closed:
            return "MCP transport is closed"
        case .timeout(let method, let seconds):
            return "MCP request '\(method)' timed out after \(seconds)s"
        case .processExited(let stderr):
            // server 进程退出（握手期最常见）：附上 stderr 末尾便于诊断「命令不存在」等问题
            return stderr.isEmpty
                ? "MCP server process exited"
                : "MCP server process exited: \(stderr)"
        case .httpStatus(let code):
            return "MCP server returned HTTP \(code)"
        case .invalidResponse(let detail):
            return "MCP server returned an invalid response: \(detail)"
        }
    }
}

/// MCP 客户端传输协议。实现必须是 actor 或保证线程安全（request 可并发挂起）。
protocol MCPClientTransport: Sendable {
    /// 发送 JSON-RPC 请求并等待 result。服务端回 error 对象时抛 MCPError。
    func request(method: String, params: [String: Any], timeout: TimeInterval) async throws -> [String: Any]
    /// 发送通知（无响应），尽力而为、不抛错。
    func notify(method: String, params: [String: Any]) async
    /// 关闭传输（终止子进程 / 放弃连接），幂等。
    func close() async
}

// MARK: - stdio 传输

#if os(macOS)
/// stdio 传输：Process 起子进程，JSON-RPC over stdin/stdout（一条消息一行）。
///
/// 注意与 RunCommandTool 的差异：stdout 是协议通道，stderr 不能合并进来
/// （会污染 JSON 流），这里单独收集 stderr 末尾若干字节用于连接失败的诊断。
actor MCPStdioTransport: MCPClientTransport {

    private let process: Process
    private let stdinHandle: FileHandle
    private var readTask: Task<Void, Never>?

    private var nextRequestID = 0
    /// 挂起中的请求：id → (continuation, 超时哨兵)。响应到达/超时/断开时结算。
    private var pending: [Int: (CheckedContinuation<[String: Any], Error>, Task<Void, Never>)] = [:]
    private var readBuffer = Data()
    private var isClosed = false
    /// stderr 末尾片段（诊断用，连接失败时附在错误信息里）
    private var stderrTail = ""

    /// - Parameter useLoginShell: true 时经 `login shell -l -i -c exec ...` 启动，
    ///   继承 nvm/pyenv 等在 rc 文件里配置的 PATH（GUI 进程环境变量是登录快照，
    ///   与 RunCommandTool 同一取舍）；测试传 false 直接启动，避免 rc 文件噪音与慢启动。
    init(command: String, args: [String], env: [String: String], useLoginShell: Bool = true) throws {
        let process = Process()
        if useLoginShell {
            let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
            process.executableURL = URL(fileURLWithPath: shell)
            let quoted = ([command] + args).map(Self.shellQuote).joined(separator: " ")
            // exec 替换 shell 进程：terminate 直接作用于 server，且不留 shell 中间层
            process.arguments = ["-l", "-i", "-c", "exec \(quoted)"]
        } else {
            process.executableURL = URL(fileURLWithPath: command)
            process.arguments = args
        }
        var environment = ProcessInfo.processInfo.environment
        for (key, value) in env { environment[key] = value }
        process.environment = environment

        let inPipe = Pipe()
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardInput = inPipe
        process.standardOutput = outPipe
        process.standardError = errPipe

        try process.run()
        self.process = process
        self.stdinHandle = inPipe.fileHandleForWriting

        // nonisolated static 启动器：init 阶段（nonisolated context）即可调用；
        // 返回的 Task 赋给 actor 状态
        self.readTask = Self.launchReadLoop(handle: outPipe.fileHandleForReading, target: self)
        Self.launchStderrDrain(handle: errPipe.fileHandleForReading, target: self)
    }

    /// shell 单引号转义（' → '\''），config 是用户自己写的，只需防意外不防攻击。
    private static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: - 读循环

    /// 阻塞读放 detached 任务；协议分发回 actor 上下文（与 MCPServer.runStdioLoop 同思路）。
    /// 强引用 target 是有意的：读循环与进程同生命周期，close() 终止进程 → EOF → 任务结束。
    private static func launchReadLoop(handle: FileHandle, target: MCPStdioTransport) -> Task<Void, Never> {
        Task.detached {
            while true {
                // 用 availableData 而非 readData(ofLength:)：后者会攒满缓冲或等 EOF 才返回，
                // 短响应（MCP 消息通常远小于 8KB）会被卡到进程退出才读到
                let chunk = handle.availableData   // 阻塞读：有数据即返回
                if chunk.isEmpty { break }         // EOF：进程退出
                await target.ingest(chunk)
            }
            await target.handleEOF()
        }
    }

    /// stderr 只作诊断收集：非协议通道，子进程可能写任意文本/进度条。
    /// 边读边留末尾 2KB，防止话痨 server 撑爆内存或阻塞管道。
    private static func launchStderrDrain(handle: FileHandle, target: MCPStdioTransport) {
        Task.detached {
            var tail = ""
            while true {
                let chunk = handle.availableData   // 同读循环：有数据即返回
                if chunk.isEmpty { break }
                tail += String(decoding: chunk, as: UTF8.self)
                if tail.count > 2048 { tail = String(tail.suffix(2048)) }
            }
            await target.setStderrTail(tail)
        }
    }

    private func setStderrTail(_ tail: String) {
        stderrTail = tail.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 喂入一段 stdout 数据：按行切分，逐行分发。
    private func ingest(_ chunk: Data) {
        readBuffer.append(chunk)
        while let newlineIndex = readBuffer.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = readBuffer.subdata(in: readBuffer.startIndex..<newlineIndex)
            readBuffer.removeSubrange(readBuffer.startIndex...newlineIndex)
            dispatch(line: String(decoding: lineData, as: UTF8.self))
        }
    }

    /// 分发一行 stdout：能解析且带整数 id 的视为响应，结算对应挂起请求；
    /// 其余（server 通知、日志噪音、login shell rc 文件的 stdout 输出）一律忽略——
    /// 宽容跳过坏行比因一行噪音断开整个连接更稳。
    private func dispatch(line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawID = obj["id"] as? NSNumber,
              CFGetTypeID(rawID) != CFBooleanGetTypeID()
        else { return }
        let id = rawID.intValue
        guard let entry = pending.removeValue(forKey: id) else { return }
        entry.1.cancel()   // 取消超时哨兵
        if let error = obj["error"] as? [String: Any] {
            let code = error["code"] as? Int ?? MCPJSONRPC.internalErrorCode
            let message = error["message"] as? String ?? "unknown error"
            entry.0.resume(throwing: MCPError(code: code, message: message))
        } else {
            entry.0.resume(returning: obj["result"] as? [String: Any] ?? [:])
        }
    }

    /// 进程退出（stdout EOF）：结算全部挂起请求，此后请求一律失败。
    /// 错误附带 stderr 末尾片段（诊断「command not found」等启动失败）。
    private func handleEOF() {
        guard !isClosed else { return }
        isClosed = true
        failAllPending(MCPTransportError.processExited(stderr: String(stderrTail.suffix(300))))
    }

    private func failAllPending(_ error: Error) {
        let entries = pending
        pending.removeAll()
        for (_, entry) in entries {
            entry.1.cancel()
            entry.0.resume(throwing: error)
        }
    }

    // MARK: - MCPClientTransport

    func request(method: String, params: [String: Any], timeout: TimeInterval) async throws -> [String: Any] {
        guard !isClosed else { throw MCPTransportError.closed }
        nextRequestID += 1
        let id = nextRequestID
        let message: [String: Any] = [
            "jsonrpc": "2.0", "id": id, "method": method, "params": params,
        ]
        let line = Data((MCPJSONRPC.serialize(message) + "\n").utf8)
        // 先登记 pending 再写请求：快 server 的响应可能在 write 返回后立刻被读循环
        // 分发，若 pending 尚未登记，响应会被当作「无主的行」丢弃，请求挂到超时
        return try await withCheckedThrowingContinuation { cont in
            let timeoutTask = Task {
                try? await Task.sleep(for: .seconds(timeout))
                guard !Task.isCancelled else { return }
                self.timeoutRequest(id: id, method: method, timeout: timeout)
            }
            pending[id] = (cont, timeoutTask)
            do {
                try stdinHandle.write(contentsOf: line)
            } catch {
                timeoutTask.cancel()
                pending.removeValue(forKey: id)
                cont.resume(throwing: MCPTransportError.closed)
            }
        }
    }

    private func timeoutRequest(id: Int, method: String, timeout: TimeInterval) {
        guard let entry = pending.removeValue(forKey: id) else { return }
        entry.0.resume(throwing: MCPTransportError.timeout(method: method, seconds: Int(timeout)))
    }

    func notify(method: String, params: [String: Any]) async {
        guard !isClosed else { return }
        let message: [String: Any] = ["jsonrpc": "2.0", "method": method, "params": params]
        try? stdinHandle.write(contentsOf: Data((MCPJSONRPC.serialize(message) + "\n").utf8))
    }

    func close() async {
        guard !isClosed else { return }
        isClosed = true
        failAllPending(MCPTransportError.closed)
        // 非交互子进程：SIGTERM 足够（不像 RunCommandTool 的交互 shell 会忽略 SIGTERM）
        if process.isRunning { process.terminate() }
        readTask?.cancel()
        try? stdinHandle.close()
    }
}
#endif

// MARK: - Streamable HTTP 传输

/// Streamable HTTP 传输：每条请求一次 POST（JSON-RPC body）。
/// 服务端可能回 application/json 或 text/event-stream（SSE 流）——SSE 简化为
/// 读完整 body 后从 data: 事件里拣出与请求 id 匹配的响应，不支持长连接推送。
actor MCPStreamableHTTPTransport: MCPClientTransport {

    private let url: URL
    private let session: any URLSessionDataProtocol
    /// streamable HTTP 的会话 id：initialize 响应头下发，后续请求必须回带
    private var sessionID: String?
    private var nextRequestID = 0
    private var isClosed = false

    init(url: URL, session: any URLSessionDataProtocol = URLSession.shared) {
        self.url = url
        self.session = session
    }

    func request(method: String, params: [String: Any], timeout: TimeInterval) async throws -> [String: Any] {
        guard !isClosed else { throw MCPTransportError.closed }
        nextRequestID += 1
        let id = nextRequestID
        let body: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method, "params": params]
        let (data, http) = try await post(body: body, timeout: timeout)
        let contentType = http.value(forHTTPHeaderField: "Content-Type") ?? ""
        let object: [String: Any]
        if contentType.contains("text/event-stream") {
            object = try Self.parseSSE(data: data, requestID: id)
        } else {
            guard let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw MCPTransportError.invalidResponse("body is not a JSON object")
            }
            object = parsed
        }
        if let error = object["error"] as? [String: Any] {
            let code = error["code"] as? Int ?? MCPJSONRPC.internalErrorCode
            let message = error["message"] as? String ?? "unknown error"
            throw MCPError(code: code, message: message)
        }
        return object["result"] as? [String: Any] ?? [:]
    }

    func notify(method: String, params: [String: Any]) async {
        guard !isClosed else { return }
        let body: [String: Any] = ["jsonrpc": "2.0", "method": method, "params": params]
        _ = try? await post(body: body, timeout: 15)
    }

    func close() async {
        isClosed = true
    }

    // MARK: - 私有

    private func post(body: [String: Any], timeout: TimeInterval) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // 同时声明接受 SSE：streamable HTTP 服务端可任选其一回包
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = timeout
        if let sessionID {
            request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw MCPTransportError.invalidResponse("not an HTTP response")
        }
        // 会话 id 以服务端最新下发为准（initialize 或任意后续响应都可能带）
        if let sid = http.value(forHTTPHeaderField: "Mcp-Session-Id"), !sid.isEmpty {
            sessionID = sid
        }
        // 202 Accepted：通知类消息无 body，调用方不应走到这里取 result
        guard (200..<300).contains(http.statusCode) else {
            throw MCPTransportError.httpStatus(http.statusCode)
        }
        return (data, http)
    }

    /// 从 SSE body 里拣出与 requestID 匹配的 JSON-RPC 响应。
    /// SSE 帧格式：事件间空行分隔，每条事件若干 "data: <json>" 行（可续行拼接）。
    static func parseSSE(data: Data, requestID: Int) throws -> [String: Any] {
        let text = String(decoding: data, as: UTF8.self)
        for event in text.components(separatedBy: "\n\n") {
            let payload = event
                .components(separatedBy: "\n")
                .filter { $0.hasPrefix("data:") }
                .map { $0.dropFirst("data:".count).trimmingCharacters(in: .init(charactersIn: " ")) }
                .joined()
            guard !payload.isEmpty,
                  let payloadData = payload.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
                  let rawID = obj["id"] as? NSNumber,
                  rawID.intValue == requestID
            else { continue }
            return obj
        }
        throw MCPTransportError.invalidResponse("no SSE event matched request id \(requestID)")
    }
}
