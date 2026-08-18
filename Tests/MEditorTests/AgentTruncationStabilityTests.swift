import XCTest
@testable import MEditor

// MARK: - AgentFileRepositoryStabilityTests
//
// Agent 稳定性回归测试（eval 集）—— DefaultAgentFileRepository 读盘截断：
//   C11 >64_000 字符的纯中文文件：完整解码后按字符截断，无乱码、截断标记数字正确；
//       小文件不附加截断标记。
// 回归背景：旧实现按字节截断会切断多字节 UTF-8 字符，导致整文回退 isoLatin1 解码（乱码）。

final class AgentFileRepositoryStabilityTests: XCTestCase {

    private var tempDir: URL!
    private var repo: DefaultAgentFileRepository!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("meditor-eval-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let dir = tempDir!
        repo = DefaultAgentFileRepository { dir }
    }

    override func tearDownWithError() throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
        repo = nil
        tempDir = nil
        try super.tearDownWithError()
    }

    // 「逆水行舟不进则退」8 字一循环 × 9000 = 72_000 字符（> 64_000 截断阈值）。
    private func makeBigChineseContent() -> String {
        String(repeating: "逆水行舟不进则退", count: 9_000)
    }

    private func assertBigFileTruncation(_ result: String, file: StaticString = #filePath, line: UInt = #line) {
        let marker = "…[truncated: showing first 64000 of 72000 characters]"
        XCTAssertTrue(result.contains(marker), "应含截断标记且 M=72000", file: file, line: line)
        XCTAssertTrue(result.hasSuffix("characters]"), "截断标记应在末尾", file: file, line: line)

        // 截断点前的 64_000 个字符必须完整无损（无乱码）
        let kept = String(result.prefix(64_000))
        XCTAssertEqual(kept.count, 64_000, "应按字符截断到 64_000", file: file, line: line)
        XCTAssertEqual(kept.first, "逆", "首字符应正确（无乱码）", file: file, line: line)
        // 第 64_000 个字符（0-based index 63_999）：63_999 % 8 == 7 → 「退」
        XCTAssertEqual(kept.last, "退", "截断点最后一个字符应正确（多字节字符未被切断）", file: file, line: line)
    }

    func test_readFileSyncFallback_largeChineseFile_truncatesWithoutMojibake() throws {
        let fileURL = tempDir.appendingPathComponent("big.md")
        try makeBigChineseContent().write(to: fileURL, atomically: true, encoding: .utf8)

        let result = try repo.readFileSyncFallback(at: fileURL)

        assertBigFileTruncation(result)
    }

    func test_readFile_async_largeChineseFile_truncatesWithoutMojibake() async throws {
        let fileURL = tempDir.appendingPathComponent("big-async.md")
        try makeBigChineseContent().write(to: fileURL, atomically: true, encoding: .utf8)

        let result = try await repo.readFile(at: fileURL)

        assertBigFileTruncation(result)
    }

    func test_readFileSyncFallback_smallChineseFile_noTruncationMarker() throws {
        let content = "你好，世界。\n这是第二行。\n"
        let fileURL = tempDir.appendingPathComponent("small.md")
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        let result = try repo.readFileSyncFallback(at: fileURL)

        XCTAssertEqual(result, content, "小文件应原样返回")
        XCTAssertFalse(result.contains("truncated"), "小文件不应有截断标记")
    }
}

// MARK: - AIConversationTruncationTests
//
//   D12 超限滑动裁剪：system 保留在头部；边界不落 tool_calls/result 配对之间；配对完整
//   D13 未超限：返回 false 且历史不变

@MainActor
final class AIConversationTruncationTests: XCTestCase {

    override func setUp() {
        super.setUp()
        clearPersistedSessions()
    }

    override func tearDown() {
        clearPersistedSessions()
        super.tearDown()
    }

    /// 与现有 AIConversationTests 相同：清掉持久化文件，避免 init 的异步 loadFromDisk 干扰。
    private func clearPersistedSessions() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MEditor", isDirectory: true)
        let fileURL = base.appendingPathComponent("ai-sessions.json")
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// 一轮完整工具对话：user → assistant(toolCalls) → tool result。
    private func makeToolRound(_ i: Int, toolContent: String) -> [AgentMessage] {
        [
            AgentMessage(role: .user, content: "question \(i)"),
            AgentMessage(
                role: .assistant,
                content: "",
                toolCalls: [AgentToolCall(id: "tc\(i)", name: "read_document", argumentsJSON: "{}")]
            ),
            AgentMessage(role: .tool, content: toolContent, toolCallID: "tc\(i)", toolName: "read_document"),
        ]
    }

    func test_truncateIfOverLimit_keepsSystemAndToolPairsIntact() {
        let conv = AIConversation()
        // 12 轮 × 50_000 字符 tool result ≈ 150k tokens > 102_400 阈值
        let bigToolContent = String(repeating: "测", count: 50_000)
        var history: [AgentMessage] = [AgentMessage(role: .system, content: "system prompt")]
        for i in 0..<12 { history.append(contentsOf: makeToolRound(i, toolContent: bigToolContent)) }
        conv.agentHistory = history

        XCTAssertTrue(conv.isApproachingContextLimit, "构造的历史必须触发超限")

        let truncated = conv.truncateIfOverLimit(keepRecentPairs: 2)
        XCTAssertTrue(truncated, "超限时应执行裁剪并返回 true")

        let newHistory = conv.agentHistory

        // system 仍在头部
        XCTAssertEqual(newHistory.first?.role, .system, "system 消息应固定在头部")

        // 裁剪边界：新历史首条（非 system）不能是 tool 消息
        let tail = Array(newHistory.dropFirst())
        XCTAssertFalse(tail.isEmpty, "裁剪后应保留最近轮次")
        XCTAssertNotEqual(tail.first?.role, .tool,
                          "裁剪边界不能落在 tool_calls/tool result 配对之间（首条为 tool）")

        // 配对完整：每个保留的 tool_call id 都有配对 result，且没有孤儿 result
        let callIDs = tail.flatMap { $0.toolCalls ?? [] }.map(\.id)
        let resultIDs = tail.compactMap { $0.role == .tool ? $0.toolCallID : nil }
        XCTAssertFalse(callIDs.isEmpty, "裁剪结果应真实保留至少一个工具轮次")
        XCTAssertEqual(Set(callIDs), Set(resultIDs),
                       "保留的 tool_call 与 tool result 必须一一配对")

        // 确定性边界：tail = 36 条，totalPairs = 4，起点 32 落在 round10 的 tool 上 → 后移到 round11 的 user
        XCTAssertEqual(tail.count, 3, "起点对齐后应保留最近一整轮（user+assistant+tool）")
        XCTAssertEqual(callIDs, ["tc11"])
    }

    func test_truncateIfOverLimit_underLimit_returnsFalseAndKeepsHistory() {
        let conv = AIConversation()
        var history: [AgentMessage] = [AgentMessage(role: .system, content: "sys")]
        history.append(contentsOf: makeToolRound(0, toolContent: "small result"))
        conv.agentHistory = history

        XCTAssertFalse(conv.isApproachingContextLimit)
        XCTAssertFalse(conv.truncateIfOverLimit(keepRecentPairs: 2), "未超限应返回 false")

        let after = conv.agentHistory
        XCTAssertEqual(after.count, history.count, "未超限时历史不应变化")
        XCTAssertEqual(after.map(\.role), history.map(\.role))
        XCTAssertEqual(after.map(\.content), history.map(\.content))
        XCTAssertEqual(after.compactMap { $0.toolCallID }, history.compactMap { $0.toolCallID })
    }

    func test_truncateIfOverLimit_firstTailMessage_isUser() {
        let conv = AIConversation()
        // 11 轮工具对话 + 末尾一条 assistant 最终回复：tail = 34 条，
        // keepRecentPairs=3（totalPairs=6）→ 朴素起点 28 落在 round9 的 assistant 上。
        // 起点对齐应把该 assistant(toolCalls) 与其 tool 结果整组丢弃，落到 round10 的 user。
        let bigToolContent = String(repeating: "测", count: 50_000)
        var history: [AgentMessage] = [AgentMessage(role: .system, content: "system prompt")]
        for i in 0..<11 { history.append(contentsOf: makeToolRound(i, toolContent: bigToolContent)) }
        history.append(AgentMessage(role: .assistant, content: "最终回复"))
        conv.agentHistory = history

        XCTAssertTrue(conv.isApproachingContextLimit, "构造的历史必须触发超限")
        XCTAssertTrue(conv.truncateIfOverLimit(keepRecentPairs: 3))

        let tail = Array(conv.agentHistory.dropFirst())   // 去掉 system
        XCTAssertEqual(tail.first?.role, .user,
                       "裁剪后首条（非 system）必须是 user（Anthropic 对 assistant 开头直接 400）")
        XCTAssertEqual(tail.count, 4, "应保留 round10 一整轮 + 末尾 assistant 回复")
        XCTAssertEqual(tail.flatMap { $0.toolCalls ?? [] }.map(\.id), ["tc10"])
        // 配对完整：无孤儿 tool result
        let callIDs = tail.flatMap { $0.toolCalls ?? [] }.map(\.id)
        let resultIDs = tail.compactMap { $0.role == .tool ? $0.toolCallID : nil }
        XCTAssertEqual(Set(callIDs), Set(resultIDs))
    }

    func test_estimatedTokenCount_includesToolCallArguments() {
        let conv = AIConversation()
        // assistant 的 toolCalls 参数（write_document 全量写入）可达数万字符：
        // 只算 content 时估算远低于真实占用，128K 横幅/截断触发时机严重滞后。
        let bigArgs = #"{"name":"doc.md","content":""# + String(repeating: "文", count: 30_000) + #""}"#
        conv.agentHistory = [
            AgentMessage(role: .user, content: "write"),
            AgentMessage(role: .assistant, content: "",
                         toolCalls: [AgentToolCall(id: "tc0", name: "write_document", argumentsJSON: bigArgs)]),
            AgentMessage(role: .tool, content: "ok", toolCallID: "tc0", toolName: "write_document"),
        ]

        let contentOnly = conv.agentHistory.reduce(0) { $0 + AIConversation.estimateTokens($1.content) }
        XCTAssertGreaterThan(conv.estimatedTokenCount, contentOnly + 15_000,
                             "toolCalls 参数 JSON 应计入 token 估算（30_000 CJK 字符 ≈ 20_000 token）")
    }
}
