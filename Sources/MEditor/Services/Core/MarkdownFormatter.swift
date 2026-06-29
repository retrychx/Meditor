import Foundation

/// 纯本地的 Markdown 规范化器（不依赖 AI）。
///
/// 设计原则：**保持 Markdown 语法与内容结构不变**，只做轻量"排版规整"：
/// - 中英文之间自动加空格（盘古之白）
/// - ATX 标题 `#` 后补一个空格
/// - 无序列表标记统一为 `-`
/// - 表格按列对齐
/// - 清理行尾空格、收敛连续空行、保证文末单个换行
///
/// 关键安全点：**围栏代码块（``` / ~~~）内的内容原样保留**，
/// 行内代码（`` `…` ``）也不参与中英文加空格，避免破坏代码。
enum MarkdownFormatter {

    // CJK 范围：汉字 + 日文假名（中文文档为主）
    private static let cjk = "\u{4e00}-\u{9fff}\u{3040}-\u{30ff}"

    static func format(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        var out: [String] = []
        out.reserveCapacity(lines.count)

        var inFence = false
        var fenceMarker = ""
        var blankRun = 0

        for raw in lines {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            let isFence = trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~")

            if isFence {
                let marker = trimmed.hasPrefix("~~~") ? "~~~" : "```"
                if !inFence {
                    inFence = true; fenceMarker = marker
                } else if trimmed.hasPrefix(fenceMarker) {
                    inFence = false; fenceMarker = ""
                }
                out.append(stripTrailing(raw))
                blankRun = 0
                continue
            }

            if inFence {
                out.append(raw)   // 代码块内：原样（含空行与缩进）
                continue
            }

            if trimmed.isEmpty {
                blankRun += 1
                if blankRun >= 2 { continue }   // 连续空行收敛为最多 1 个
                out.append("")
                continue
            }
            blankRun = 0

            var l = raw
            l = normalizeHeading(l)
            l = normalizeUnorderedList(l)
            l = spaceCJKLatin(l)
            l = stripTrailing(l)
            out.append(l)
        }

        var result = out.joined(separator: "\n")
        result = alignTables(result)
        result = String(result.drop(while: { $0 == "\n" }))
        while result.hasSuffix("\n") { result.removeLast() }
        return result.isEmpty ? "" : result + "\n"
    }

    // MARK: - Line-level rules

    private static func stripTrailing(_ line: String) -> String {
        var l = line
        while let last = l.last, last == " " || last == "\t" { l.removeLast() }
        return l
    }

    /// `##标题` → `## 标题`（ATX 标题 # 后补空格），已有空格则不动。
    private static func normalizeHeading(_ line: String) -> String {
        replace(line, pattern: "^(#{1,6})([^#\\s])", template: "$1 $2")
    }

    /// 行首无序列表标记 `*` / `+` 统一为 `-`（需后跟空格，避免误伤 `***` 分隔线或 `*强调*`）。
    private static func normalizeUnorderedList(_ line: String) -> String {
        replace(line, pattern: "^(\\s*)[*+](\\s+)", template: "$1-$2")
    }

    /// 中英文之间加空格，保护行内代码段不被改动。
    private static func spaceCJKLatin(_ line: String) -> String {
        guard line.range(of: "[\(cjk)]", options: .regularExpression) != nil else { return line }

        // 抽出行内代码 `…`，用 NUL 占位，处理完再还原
        var codeSpans: [String] = []
        let ns = line as NSString
        guard let codeRegex = try? NSRegularExpression(pattern: "`[^`\\n]+`") else {
            return applyCJKSpacing(line)
        }
        var placeholder = ""
        var last = 0
        for m in codeRegex.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
            let r = m.range
            placeholder += ns.substring(with: NSRange(location: last, length: r.location - last))
            placeholder += "\u{0000}\(codeSpans.count)\u{0000}"
            codeSpans.append(ns.substring(with: r))
            last = r.location + r.length
        }
        placeholder += ns.substring(from: last)

        var spaced = applyCJKSpacing(placeholder)
        for (i, code) in codeSpans.enumerated() {
            spaced = spaced.replacingOccurrences(of: "\u{0000}\(i)\u{0000}", with: code)
        }
        return spaced
    }

    private static func applyCJKSpacing(_ s: String) -> String {
        var r = replace(s, pattern: "([\(cjk)])([A-Za-z0-9])", template: "$1 $2")
        r = replace(r, pattern: "([A-Za-z0-9])([\(cjk)])", template: "$1 $2")
        return r
    }

    // MARK: - Table alignment

    private static func alignTables(_ text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        var inFence = false
        var fenceMarker = ""
        var i = 0
        while i < lines.count {
            let t = lines[i].trimmingCharacters(in: .whitespaces)
            let isFence = t.hasPrefix("```") || t.hasPrefix("~~~")
            if isFence {
                let marker = t.hasPrefix("~~~") ? "~~~" : "```"
                if !inFence { inFence = true; fenceMarker = marker }
                else if t.hasPrefix(fenceMarker) { inFence = false; fenceMarker = "" }
                i += 1; continue
            }
            if inFence { i += 1; continue }

            if i + 1 < lines.count, isTableRow(lines[i]), isSeparatorRow(lines[i + 1]) {
                var j = i + 2
                while j < lines.count, isTableRow(lines[j]) { j += 1 }
                let block = Array(lines[i..<j])
                let aligned = alignTableBlock(block)
                if aligned.count == block.count {
                    for k in 0..<block.count { lines[i + k] = aligned[k] }
                }
                i = j; continue
            }
            i += 1
        }
        return lines.joined(separator: "\n")
    }

    private static func isTableRow(_ line: String) -> Bool {
        line.contains("|")
    }

    private static func isSeparatorRow(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.contains("-") else { return false }
        return t.range(of: "^\\|?[\\s:|-]+\\|?$", options: .regularExpression) != nil
    }

    private enum ColAlign { case left, right, center, none }

    private static func splitCells(_ row: String) -> [String] {
        var s = row.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("|") { s.removeFirst() }
        if s.hasSuffix("|") { s.removeLast() }
        return s.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func alignTableBlock(_ block: [String]) -> [String] {
        guard block.count >= 2 else { return block }
        let header = splitCells(block[0])
        let sep    = splitCells(block[1])
        let colCount = header.count
        guard colCount > 0, sep.count == colCount else { return block }

        let rows = block.enumerated().map { idx, line -> [String] in
            idx == 1 ? [] : splitCells(line)
        }
        // 任一数据行列数不一致 → 放弃对齐，原样返回（避免破坏）
        for (idx, cells) in rows.enumerated() where idx != 1 {
            if cells.count != colCount { return block }
        }

        let aligns: [ColAlign] = sep.map { cell in
            let c = cell.trimmingCharacters(in: .whitespaces)
            let l = c.hasPrefix(":"), r = c.hasSuffix(":")
            if l && r { return .center }
            if r { return .right }
            if l { return .left }
            return .none
        }

        // 列宽 = 该列所有单元格字符数最大值，且 >= 3
        var widths = [Int](repeating: 3, count: colCount)
        for (idx, cells) in rows.enumerated() where idx != 1 {
            for c in 0..<colCount { widths[c] = max(widths[c], cells[c].count) }
        }

        func pad(_ s: String, _ w: Int, _ a: ColAlign) -> String {
            let gap = max(0, w - s.count)
            switch a {
            case .right:
                return String(repeating: " ", count: gap) + s
            case .center:
                let l = gap / 2, r = gap - l
                return String(repeating: " ", count: l) + s + String(repeating: " ", count: r)
            default:
                return s + String(repeating: " ", count: gap)
            }
        }

        func sepCell(_ w: Int, _ a: ColAlign) -> String {
            switch a {
            case .center: return ":" + String(repeating: "-", count: max(1, w - 2)) + ":"
            case .right:  return String(repeating: "-", count: max(1, w - 1)) + ":"
            case .left:   return ":" + String(repeating: "-", count: max(1, w - 1))
            case .none:   return String(repeating: "-", count: w)
            }
        }

        var result: [String] = []
        for (idx, cells) in rows.enumerated() {
            if idx == 1 {
                let parts = (0..<colCount).map { sepCell(widths[$0], aligns[$0]) }
                result.append("| " + parts.joined(separator: " | ") + " |")
            } else {
                let parts = (0..<colCount).map { pad(cells[$0], widths[$0], aligns[$0]) }
                result.append("| " + parts.joined(separator: " | ") + " |")
            }
        }
        return result
    }

    // MARK: - Regex helper

    private static func replace(_ s: String, pattern: String, template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return s }
        let range = NSRange(location: 0, length: (s as NSString).length)
        return regex.stringByReplacingMatches(in: s, range: range, withTemplate: template)
    }
}
