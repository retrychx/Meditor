import Foundation

/// Safe Swift → JavaScript string bridge.
///
/// All string values passed into `evaluateJavaScript` must go through
/// `JSBridge.encode()` to prevent injection via special characters
/// (backslash, newline, NUL, HTML-unsafe chars).
///
/// Usage:
/// ```swift
/// webView.evaluateJavaScript(
///     JSBridge.call("setTheme", args: [theme.rawValue]),
///     completionHandler: nil
/// )
/// ```
enum JSBridge {

    /// JSON-encode a Swift String into a JavaScript string literal (with quotes).
    static func encode(_ string: String) -> String {
        guard let data = try? JSONEncoder().encode(string),
              let json = String(data: data, encoding: .utf8) else {
            // Manual fallback: escape special chars
            let escaped = string
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
                .replacingOccurrences(of: "\t", with: "\\t")
            return "\"\(escaped)\""
        }
        return json
    }

    /// Build a `window.MEditor.<function>(arg1, arg2, ...)` call string.
    /// All string args are JSON-encoded so no injection is possible.
    static func call(_ function: String, args: [String] = []) -> String {
        let encodedArgs = args.map { encode($0) }.joined(separator: ", ")
        return "window.MEditor && window.MEditor.\(function)(\(encodedArgs));"
    }

    /// Build a `window.MEditor.<function>(arg)` call for a single integer argument.
    static func call(_ function: String, intArg: Int) -> String {
        return "window.MEditor && window.MEditor.\(function)(\(intArg));"
    }
}
