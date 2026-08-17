import XCTest
@testable import MEditor

// MARK: - ClaudeCLIBackendParseTests
//
// 回归：_parse_error 的 errJSON 曾手工拼接字符串，工具名 / 原始参数含引号、
// 反斜杠、换行时会产出非法 JSON（AI 拿到后无法解析，重试链路断裂）。
// 修复后走 JSONSerialization 构造——任何内容都必须产出合法 JSON。

final class ClaudeCLIBackendParseTests: XCTestCase {

    private func makeBackend() -> ClaudeCLIBackend {
        // parseToolCalls 不读 config，任意配置即可
        ClaudeCLIBackend(config: AIConfig(
            kind: .openai,
            baseURL: "",
            model: "",
            cliPath: "/usr/bin/true",
            cliModel: "",
            apiKey: "",
            requestTimeoutSeconds: 60
        ))
    }

    // MARK: - 工具名含引号 / 参数含引号、反斜杠、换行 → _parse_error 仍是合法 JSON

    func test_parseError_specialCharsInNameAndArgs_producesValidJSON() throws {
        let text = #"""
        <tool_call>
        <name>write"file\x</name>
        <arguments>{"path": "a\"b
        "c}</arguments>
        </tool_call>
        """#

        let calls = makeBackend().parseToolCalls(from: text)
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0].name, "_parse_error", "无法修复的参数必须降级为 _parse_error")

        let data = try XCTUnwrap(calls[0].rawArgumentsJSON?.data(using: .utf8))
        let obj = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any],
            "_parse_error 的 rawArgumentsJSON 必须是合法 JSON（手工拼接在此会产出非法 JSON）"
        )
        XCTAssertEqual(obj["original_tool"] as? String, #"write"file\x"#, "工具名必须原样保留")
        XCTAssertTrue((obj["raw_arguments"] as? String)?.contains("\"path\"") ?? false,
                      "原始参数必须原样保留供 AI 参照重试")
        XCTAssertNotNil(obj["error"])
    }

    // MARK: - 普通畸形参数 → _parse_error，字段齐全

    func test_parseError_plainMalformedArgs_producesValidJSON() throws {
        let text = """
        <tool_call><name>read_document</name><arguments>{invalid json</arguments></tool_call>
        """

        let calls = makeBackend().parseToolCalls(from: text)
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0].name, "_parse_error")

        let data = try XCTUnwrap(calls[0].rawArgumentsJSON?.data(using: .utf8))
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(obj["original_tool"] as? String, "read_document")
        XCTAssertEqual(obj["raw_arguments"] as? String, "{invalid json")
        XCTAssertNotNil(obj["error"])
    }

    // MARK: - 基线：合法参数原样透传，不误伤正常路径

    func test_parse_validArgs_passThroughUnchanged() {
        let text = """
        <tool_call><name>read_document</name><arguments>{"file": "a.md"}</arguments></tool_call>
        """

        let calls = makeBackend().parseToolCalls(from: text)
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0].name, "read_document")
        XCTAssertEqual(calls[0].rawArgumentsJSON, #"{"file": "a.md"}"#)
    }
}
