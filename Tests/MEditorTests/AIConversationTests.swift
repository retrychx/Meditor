import XCTest
@testable import MEditor

@MainActor
final class AIConversationTests: XCTestCase {
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
}
