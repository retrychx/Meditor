import XCTest
@testable import MEditor

@MainActor
final class AIConversationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        clearPersistedSessions()
    }

    override func tearDown() {
        clearPersistedSessions()
        super.tearDown()
    }

    private func clearPersistedSessions() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MEditor", isDirectory: true)
        let fileURL = base.appendingPathComponent("ai-sessions.json")
        try? FileManager.default.removeItem(at: fileURL)
    }

    func testStartsEmpty() {
        let conv = AIConversation()
        XCTAssertTrue(conv.messages.isEmpty)
    }

    func testAppendMessage() {
        let conv = AIConversation()
        conv.messages = [AIChatMessage(role: .user, text: "Hello")]
        XCTAssertEqual(conv.messages.count, 1)
        XCTAssertEqual(conv.messages.first?.text, "Hello")
    }

    func testNewSessionResetsMessages() {
        let conv = AIConversation()
        conv.messages = [AIChatMessage(role: .user, text: "x")]
        conv.newSession()
        XCTAssertTrue(conv.messages.isEmpty)
    }

    func testAppendToLastMessageAccumulatesText() {
        let conv = AIConversation()
        conv.messages = [AIChatMessage(role: .assistant, text: "Hello")]
        conv.appendToLastMessage(", world")
        XCTAssertEqual(conv.messages.last?.text, "Hello, world")
    }

    func testInputDefaultsToEmpty() {
        let conv = AIConversation()
        XCTAssertTrue(conv.input.isEmpty)
    }

    // MARK: - Message cap

    func testMessageCapEnforced() {
        let conv = AIConversation()
        let over = AIConversation.maxMessagesPerSession + 10
        // seed (user) + 99 tail = exactly maxMessagesPerSession after capping
        conv.messages = (0..<over).map { AIChatMessage(role: .user, text: "msg \($0)") }
        XCTAssertEqual(conv.messages.count, AIConversation.maxMessagesPerSession)
    }

    func testFirstUserMessageRetainedAfterCap() {
        let conv = AIConversation()
        let seed = AIChatMessage(role: .user, text: "SEED")
        let rest = (0..<AIConversation.maxMessagesPerSession).map {
            AIChatMessage(role: .assistant, text: "reply \($0)")
        }
        conv.messages = [seed] + rest
        // Seed id should still be present somewhere in capped messages
        XCTAssertTrue(conv.messages.contains { $0.id == seed.id },
                      "first user message must be retained as seed context")
    }

    // MARK: - Token estimation

    func testEstimatedTokenCount() {
        let conv = AIConversation()
        // 40 chars ÷ 4 = 10 tokens
        conv.messages = [AIChatMessage(role: .user, text: String(repeating: "x", count: 40))]
        XCTAssertEqual(conv.estimatedTokenCount, 10)
    }

    func testIsApproachingContextLimit_false() {
        let conv = AIConversation()
        conv.messages = [AIChatMessage(role: .user, text: "hi")]
        XCTAssertFalse(conv.isApproachingContextLimit)
    }

    func testIsApproachingContextLimit_true() {
        let conv = AIConversation()
        // 102_401 × 4 = 409_604 chars > threshold
        conv.messages = [AIChatMessage(role: .user, text: String(repeating: "a", count: 102_401 * 4))]
        XCTAssertTrue(conv.isApproachingContextLimit)
    }

    // MARK: - Token estimation 指纹缓存

    func testEstimatedTokenCountCacheConsistentAcrossEvaluations() {
        let conv = AIConversation()
        conv.messages = [AIChatMessage(role: .user, text: "你好，世界 hello")]
        // 指纹未变时连续求值必须一致（走缓存路径）
        let first  = conv.estimatedTokenCount
        let second = conv.estimatedTokenCount
        let third  = conv.estimatedTokenCount
        XCTAssertEqual(first, second)
        XCTAssertEqual(second, third)
    }

    func testEstimatedTokenCountCacheInvalidatesOnTextGrowth() {
        let conv = AIConversation()
        conv.messages = [AIChatMessage(role: .assistant, text: "short")]
        let before = conv.estimatedTokenCount
        // 流式 append 改变最后一条消息长度 → 指纹变化 → 缓存失效重算
        conv.appendToLastMessage(String(repeating: "x", count: 400))
        let after = conv.estimatedTokenCount
        XCTAssertGreaterThan(after, before)
        XCTAssertEqual(after, before + 100)   // 400 拉丁字符 ÷ 4
    }

    func testEstimatedTokenCountCacheInvalidatesOnNewMessage() {
        let conv = AIConversation()
        conv.messages = [AIChatMessage(role: .user, text: "hi")]
        let before = conv.estimatedTokenCount
        conv.messages.append(AIChatMessage(role: .assistant, text: String(repeating: "y", count: 40)))
        XCTAssertEqual(conv.estimatedTokenCount, before + 10)
    }

    func testIsApproachingContextLimitCacheConsistent() {
        let conv = AIConversation()
        conv.messages = [AIChatMessage(role: .user, text: "hi")]
        XCTAssertEqual(conv.isApproachingContextLimit, conv.isApproachingContextLimit)
        conv.messages = [AIChatMessage(role: .user, text: String(repeating: "a", count: 102_401 * 4))]
        XCTAssertTrue(conv.isApproachingContextLimit)
    }

    // MARK: - Session lifecycle

    func testDeleteLastSessionCreatesNew() {
        let conv = AIConversation()
        let originalID = conv.activeID
        conv.delete(originalID)
        XCTAssertNotEqual(conv.activeID, originalID, "a new session should be auto-created")
        XCTAssertTrue(conv.messages.isEmpty)
    }

    func testActivateSwitchesSession() {
        let conv = AIConversation()
        conv.messages = [AIChatMessage(role: .user, text: "first session")]
        conv.newSession()
        let secondID = conv.activeID

        // Activate the history entry that has messages
        let historySessions = conv.history
        guard let other = historySessions.first(where: { $0.id != secondID }) else {
            XCTFail("expected two sessions in history")
            return
        }
        conv.activate(other.id)
        XCTAssertEqual(conv.activeID, other.id)
    }

    // MARK: - 在途 run 收尾不污染新会话

    func testLateRunCompletionWritesToOriginatingSession() {
        let conv = AIConversation()
        let oldID = conv.activeID
        let reply = AIChatMessage(role: .assistant, text: "")
        conv.messages = [AIChatMessage(role: .user, text: "旧问题"), reply]

        // 模拟 run 进行中：运行快照挂在旧会话上
        let oldRunState = AgentRunState()
        conv.lastRunState = oldRunState

        // run 进行中新建会话（cancelStreaming 后旧 run 的 onComplete 仍会迟到触发）
        conv.newSession()
        let newID = conv.activeID
        XCTAssertNotEqual(oldID, newID)
        XCTAssertNil(conv.lastRunState, "lastRunState per-session：新会话不应继承旧 run 的步骤面板")

        // 旧 run 迟到的收尾：按会话 id 写回发起会话
        conv.updateMessageText("旧回答", messageID: reply.id, sessionID: oldID)
        conv.setAgentHistory([AgentMessage(role: .assistant, content: "旧回答")], sessionID: oldID)
        conv.setLastRunState(oldRunState, sessionID: oldID)

        // 新会话未被污染
        XCTAssertTrue(conv.messages.isEmpty)
        XCTAssertTrue(conv.agentHistory.isEmpty)
        XCTAssertNil(conv.lastRunState)

        // 切回旧会话：数据已正确落回（消息 / agentHistory / 步骤面板）
        conv.activate(oldID)
        XCTAssertEqual(conv.messages.last?.text, "旧回答")
        XCTAssertEqual(conv.agentHistory.first?.content, "旧回答")
        XCTAssertTrue(conv.lastRunState === oldRunState)
    }

    func testLateWritesToDeletedSessionAreDropped() {
        let conv = AIConversation()
        let oldID = conv.activeID
        conv.messages = [AIChatMessage(role: .user, text: "x")]
        conv.newSession()
        conv.delete(oldID)

        // 会话已删除：迟到写入静默丢弃，不崩溃、不写活跃会话
        conv.updateMessageText("late", messageID: UUID(), sessionID: oldID)
        conv.setAgentHistory([AgentMessage(role: .assistant, content: "late")], sessionID: oldID)
        conv.setLastRunState(AgentRunState(), sessionID: oldID)

        XCTAssertTrue(conv.agentHistory.isEmpty)
        XCTAssertNil(conv.lastRunState)
    }

    func testLastRunStateIsPerSession() {
        let conv = AIConversation()
        let firstID = conv.activeID
        conv.messages = [AIChatMessage(role: .user, text: "x")]
        let runState = AgentRunState()
        conv.lastRunState = runState

        conv.newSession()
        XCTAssertNil(conv.lastRunState, "新会话不应看到旧会话的步骤面板")

        // 通过活跃会话代理写入，跟随当前会话
        let newRunState = AgentRunState()
        conv.lastRunState = newRunState

        conv.activate(firstID)
        XCTAssertTrue(conv.lastRunState === runState, "切回旧会话应恢复它自己的步骤面板")
    }
}
