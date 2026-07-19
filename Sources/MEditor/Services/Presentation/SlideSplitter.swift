import Foundation

/// 演讲模式的 Markdown 分页器。
///
/// 规则：
/// - 单独一行的 `---`（可含前后空白）是分页符；
/// - 文档开头的 YAML front matter（首行 `---` 起、下一个 `---` 止）整体剥离，不算分页；
/// - ``` / ~~~ 代码 fence 内的 `---` 不算分页；
/// - 无分页符时整个文档作为唯一一页返回（至少返回一页）。
enum SlideSplitter {

    static func split(_ markdown: String) -> [String] {
        let lines = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")

        var startIndex = 0

        // 剥离文档开头的 YAML front matter
        if let first = lines.first, isSeparator(first) {
            for i in 1..<lines.count where isSeparator(lines[i]) {
                startIndex = i + 1
                break
            }
        }

        var slides: [String] = []
        var current: [String] = []
        var fenceMarker: String? = nil  // "```" 或 "~~~"，nil 表示不在 fence 内

        for i in startIndex..<lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // fence 开关：行首（可缩进）的 ``` 或 ~~~
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                let marker = String(trimmed.prefix(3))
                if fenceMarker == nil {
                    fenceMarker = marker
                } else if fenceMarker == marker {
                    fenceMarker = nil
                }
                current.append(line)
                continue
            }

            if fenceMarker == nil, isSeparator(line) {
                slides.append(current.joined(separator: "\n"))
                current = []
                continue
            }
            current.append(line)
        }
        slides.append(current.joined(separator: "\n"))

        // 去掉全是空白的页（如连续两个分页符产生的空页）
        let nonEmpty = slides.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return nonEmpty.isEmpty ? [""] : nonEmpty
    }

    /// 是否单独一行的分页符（允许前后空白，兼容行尾 \r）。
    private static func isSeparator(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespacesAndNewlines) == "---"
    }
}
