import XCTest
@testable import MEditor

// MARK: - AnySendableValue Codable Roundtrip Tests
//
// 验证 AnySendableValue Codable 实现在各种 JSON 边界情况下的正确性。
// 这是 agent 工具参数序列化的核心路径，任何静默丢弃都会导致 AI 行为异常。

final class AnySendableValueCodableTests: XCTestCase {

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - 基础类型 Roundtrip

    func test_string_roundtrip() throws {
        let original = AnySendableValue.string("hello world")
        let decoded  = try roundtrip(original)
        XCTAssertEqual(decoded, original)
    }

    func test_string_withUnicode_roundtrip() throws {
        let original = AnySendableValue.string("你好 🌙 \"quoted\" \n newline")
        XCTAssertEqual(try roundtrip(original), original)
    }

    func test_bool_true_roundtrip() throws {
        XCTAssertEqual(try roundtrip(.bool(true)),  .bool(true))
    }

    func test_bool_false_roundtrip() throws {
        XCTAssertEqual(try roundtrip(.bool(false)), .bool(false))
    }

    func test_int_roundtrip() throws {
        XCTAssertEqual(try roundtrip(.int(42)),     .int(42))
        XCTAssertEqual(try roundtrip(.int(-999)),   .int(-999))
        XCTAssertEqual(try roundtrip(.int(0)),      .int(0))
    }

    func test_double_roundtrip() throws {
        XCTAssertEqual(try roundtrip(.double(3.14)), .double(3.14))
        XCTAssertEqual(try roundtrip(.double(-0.5)), .double(-0.5))
    }

    func test_null_roundtrip() throws {
        XCTAssertEqual(try roundtrip(.null), .null)
    }

    // MARK: - 复合类型 Roundtrip

    func test_array_of_strings_roundtrip() throws {
        let original = AnySendableValue.array([.string("a"), .string("b"), .string("c")])
        XCTAssertEqual(try roundtrip(original), original)
    }

    func test_array_mixed_types_roundtrip() throws {
        let original = AnySendableValue.array([.string("text"), .int(42), .bool(true), .null])
        XCTAssertEqual(try roundtrip(original), original)
    }

    func test_array_empty_roundtrip() throws {
        XCTAssertEqual(try roundtrip(.array([])), .array([]))
    }

    func test_dict_roundtrip() throws {
        let original = AnySendableValue.dict([
            "name":    .string("Alice"),
            "age":     .int(30),
            "active":  .bool(true),
            "score":   .double(9.5),
            "nothing": .null
        ])
        XCTAssertEqual(try roundtrip(original), original)
    }

    func test_nested_dict_in_array_roundtrip() throws {
        let original = AnySendableValue.array([
            .dict(["key": .string("val1")]),
            .dict(["key": .string("val2"), "n": .int(2)])
        ])
        XCTAssertEqual(try roundtrip(original), original)
    }

    func test_deeply_nested_roundtrip() throws {
        let original = AnySendableValue.dict([
            "level1": .dict([
                "level2": .dict([
                    "level3": .array([.string("deep"), .int(3)])
                ])
            ])
        ])
        XCTAssertEqual(try roundtrip(original), original)
    }

    // MARK: - AgentToolCall Roundtrip（工具参数完整链路）

    func test_agentToolCall_roundtrip() throws {
        let call = AgentToolCall(
            id: "call_abc123",
            name: "patch_document",
            arguments: [
                "find":    .string("old text"),
                "replace": .string("new text"),
                "all":     .bool(false)
            ]
        )
        let data    = try encoder.encode(call)
        let decoded = try decoder.decode(AgentToolCall.self, from: data)
        XCTAssertEqual(decoded.id,   call.id)
        XCTAssertEqual(decoded.name, call.name)
        XCTAssertEqual(decoded.arguments["find"],    .string("old text"))
        XCTAssertEqual(decoded.arguments["replace"], .string("new text"))
        XCTAssertEqual(decoded.arguments["all"],     .bool(false))
    }

    func test_agentToolCall_emptyArgs_roundtrip() throws {
        let call    = AgentToolCall(id: "tc1", name: "read_document")
        let data    = try encoder.encode(call)
        let decoded = try decoder.decode(AgentToolCall.self, from: data)
        XCTAssertTrue(decoded.arguments.isEmpty)
    }

    func test_agentToolCall_complexArgs_roundtrip() throws {
        // 嵌套参数：create_file with metadata object
        let call = AgentToolCall(
            id: "tc_complex",
            name: "create_file",
            arguments: [
                "filename": .string("report.md"),
                "metadata": .dict([
                    "tags":    .array([.string("ai"), .string("report")]),
                    "version": .int(1)
                ])
            ]
        )
        let data    = try encoder.encode(call)
        let decoded = try decoder.decode(AgentToolCall.self, from: data)

        if case .dict(let meta) = decoded.arguments["metadata"] {
            XCTAssertEqual(meta["version"], .int(1))
            if case .array(let tags) = meta["tags"] {
                XCTAssertEqual(tags, [.string("ai"), .string("report")])
            } else {
                XCTFail("tags should be an array")
            }
        } else {
            XCTFail("metadata should be a dict")
        }
    }

    // MARK: - AISession agentHistory Roundtrip

    func test_aiSession_agentHistory_roundtrip() throws {
        var session = AISession()
        session.agentHistory = [
            AgentMessage(role: .user,      content: "请帮我写一个函数"),
            AgentMessage(role: .assistant, content: "", toolCalls: [
                AgentToolCall(id: "tc1", name: "read_document", arguments: [:])
            ]),
            AgentMessage(role: .tool,      content: "文档内容：...", toolCallID: "tc1", toolName: "read_document"),
            AgentMessage(role: .assistant, content: "好的，我已经读取了文档")
        ]
        let data    = try encoder.encode(session)
        let decoded = try decoder.decode(AISession.self, from: data)

        XCTAssertEqual(decoded.agentHistory.count, 4)
        XCTAssertEqual(decoded.agentHistory[0].role, .user)
        XCTAssertEqual(decoded.agentHistory[1].toolCalls?.count, 1)
        XCTAssertEqual(decoded.agentHistory[2].toolCallID, "tc1")
        XCTAssertEqual(decoded.agentHistory[3].content, "好的，我已经读取了文档")
    }

    // MARK: - Edge Cases

    func test_stringValue_helper() {
        XCTAssertEqual(AnySendableValue.string("hello").stringValue, "hello")
        XCTAssertNil(AnySendableValue.int(42).stringValue)
        XCTAssertNil(AnySendableValue.null.stringValue)
    }

    // MARK: - Helper

    private func roundtrip(_ value: AnySendableValue) throws -> AnySendableValue {
        let data = try encoder.encode(value)
        return try decoder.decode(AnySendableValue.self, from: data)
    }
}

// MARK: - Equatable for test assertions

extension AnySendableValue: Equatable {
    public static func == (lhs: AnySendableValue, rhs: AnySendableValue) -> Bool {
        switch (lhs, rhs) {
        case (.string(let a),  .string(let b)):  return a == b
        case (.bool(let a),    .bool(let b)):    return a == b
        case (.int(let a),     .int(let b)):     return a == b
        case (.double(let a),  .double(let b)):  return a == b
        case (.null,           .null):           return true
        case (.array(let a),   .array(let b)):   return a == b
        case (.dict(let a),    .dict(let b)):    return a == b
        default:                                 return false
        }
    }
}
