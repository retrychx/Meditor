import XCTest
@testable import MEditor

final class JSBridgeTests: XCTestCase {

    // MARK: - encode

    func testEncodeOrdinaryString() {
        let result = JSBridge.encode("hello")
        XCTAssertEqual(result, "\"hello\"")
    }

    func testEncodeEscapesDoubleQuote() {
        let result = JSBridge.encode("say \"hi\"")
        XCTAssertTrue(result.contains("\\\""), "double quote must be escaped")
    }

    func testEncodeEscapesBackslash() {
        let result = JSBridge.encode("path\\to\\file")
        XCTAssertTrue(result.contains("\\\\"), "backslash must be escaped")
    }

    func testEncodeEscapesNewline() {
        let result = JSBridge.encode("line1\nline2")
        XCTAssertTrue(result.contains("\\n"), "newline must be escaped")
    }

    func testEncodeBlocksScriptTag() {
        // JSONEncoder HTML-escapes '<' so </script> injection is blocked.
        let result = JSBridge.encode("</script>")
        XCTAssertFalse(result.contains("</script>"), "raw </script> must not appear in output")
    }

    func testEncodeEmptyString() {
        let result = JSBridge.encode("")
        XCTAssertEqual(result, "\"\"")
    }

    // MARK: - call(_:args:)

    func testCallNoArgs() {
        let result = JSBridge.call("init")
        XCTAssertEqual(result, "window.MEditor && window.MEditor.init();")
    }

    func testCallSingleStringArg() {
        let result = JSBridge.call("setTheme", args: ["dark"])
        XCTAssertEqual(result, "window.MEditor && window.MEditor.setTheme(\"dark\");")
    }

    func testCallMultipleArgs() {
        let result = JSBridge.call("move", args: ["a", "b"])
        XCTAssertEqual(result, "window.MEditor && window.MEditor.move(\"a\", \"b\");")
    }

    // MARK: - call(_:intArg:)

    func testCallIntArg() {
        let result = JSBridge.call("scrollTo", intArg: 42)
        XCTAssertEqual(result, "window.MEditor && window.MEditor.scrollTo(42);")
    }

    func testCallIntArgZero() {
        let result = JSBridge.call("scrollTo", intArg: 0)
        XCTAssertEqual(result, "window.MEditor && window.MEditor.scrollTo(0);")
    }
}
