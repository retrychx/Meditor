import Foundation

/// 把「渲染后预览里圈选的纯文本」映射回 Markdown 源码范围。
///
/// 为什么需要：预览里的选区来自渲染后的 HTML，丢失了 Markdown 语法
/// （`**`、`##`、`- `、链接括号等）。直接在源码里做字面查找会：
///  - 命中 `**加粗**` 的内部，替换后留下 orphaned `**` 标记；
///  - 块级选区（列表、多段）因源文带 `- ` 前缀而完全找不到。
///
/// 做法：把源码按行剥离块级标记、按字符剥离行内标记，生成
/// 「纯文本 + 每个字符对应的源码位置」映射，在归一化空白后查找选区，
/// 再把命中范围还原成源码区间，并向两侧吞掉紧邻的行内标记。
enum SourceTextMapper {

    /// 选区在源码中的范围；nil = 无法定位（调用方应提示而非兜底乱改）。
    static func sourceRange(ofPlainSelection selection: String, in source: String) -> Range<String.Index>? {
        // 1. 生成纯文本 + 位置映射
        var plain = ""
        var srcOf: [String.Index] = []   // plain 中第 i 个字符 → 源码 index
        let lines = source.components(separatedBy: "\n")
        var lineStart = source.startIndex

        for (lineIdx, line) in lines.enumerated() {
            let stripped = stripBlockPrefix(line)
            let isFence = isFenceLine(line) || isTableSeparator(line)
            if !isFence {
                var i = stripped
                while i < line.endIndex {
                    let ch = line[i]
                    let next = line.index(after: i)
                    // 转义：\* 渲染为 *，映射到 * 本身
                    if ch == "\\", next < line.endIndex {
                        plain.append(line[next])
                        srcOf.append(next)
                        i = line.index(after: next)
                        continue
                    }
                    // 图片：整体丢弃（渲染为图，无文本）
                    if ch == "!", next < line.endIndex, line[next] == "[",
                       let close = line.range(of: "](", range: next..<line.endIndex),
                       let end = line.range(of: ")", range: close.upperBound..<line.endIndex) {
                        i = end.upperBound
                        continue
                    }
                    // 链接文字保留、目标丢弃：](url)
                    if ch == "]", next < line.endIndex, line[next] == "(",
                       let end = line.range(of: ")", range: next..<line.endIndex) {
                        i = end.upperBound
                        continue
                    }
                    // HTML 标签丢弃
                    if ch == "<", let gt = line.range(of: ">", range: next..<line.endIndex) {
                        i = gt.upperBound
                        continue
                    }
                    // 行内标记与表格管道：不进入纯文本
                    if ch == "*" || ch == "_" || ch == "`" || ch == "~" || ch == "[" || ch == "|" {
                        i = next
                        continue
                    }
                    plain.append(ch)
                    srcOf.append(source.index(lineStart, offsetBy: line.distance(from: line.startIndex, to: i)))
                    i = next
                }
            }
            if lineIdx < lines.count - 1 {
                plain.append("\n")
                srcOf.append(source.index(lineStart, offsetBy: line.count))
            }
            lineStart = source.index(lineStart, offsetBy: line.count + 1, limitedBy: source.endIndex) ?? source.endIndex
        }

        // 2. 空白归一化（连续空白 → 单空格），保留 norm 字符 → plain 下标映射
        var norm = ""
        var normToPlain: [Int] = []
        var pendingSpace = false
        for (idx, ch) in plain.enumerated() {
            if ch.isWhitespace {
                pendingSpace = !norm.isEmpty
            } else {
                if pendingSpace { norm.append(" "); normToPlain.append(idx > 0 ? idx - 1 : 0) }
                pendingSpace = false
                norm.append(ch)
                normToPlain.append(idx)
            }
        }
        let needle = normalize(selection)
        guard !needle.isEmpty,
              let hit = norm.range(of: needle, options: .literal) else { return nil }

        // 3. norm 命中 → plain 下标 → 源码区间
        let hitStart = norm.distance(from: norm.startIndex, to: hit.lowerBound)
        let hitEnd = norm.distance(from: norm.startIndex, to: hit.upperBound) - 1
        var start = srcOf[normToPlain[hitStart]]
        var end = source.index(after: srcOf[normToPlain[hitEnd]])

        // 4. 向两侧吞掉紧邻的行内标记（**加粗**、~~删~~、`码`）
        let markers: Set<Character> = ["*", "_", "`", "~"]
        while start > source.startIndex, markers.contains(source[source.index(before: start)]) {
            start = source.index(before: start)
        }
        while end < source.endIndex, markers.contains(source[end]) {
            end = source.index(after: end)
        }
        return start..<end
    }

    /// 与正文一致的空白归一化。
    private static func normalize(_ s: String) -> String {
        s.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// 剥离行首块级标记（标题/引用/列表），返回正文起点。
    private static func stripBlockPrefix(_ line: String) -> String.Index {
        let patterns = [
            #"^\s{0,3}[-*+]\s+\[[ xX]\]\s+"#, // 任务列表（须先于普通列表匹配）
            #"^\s{0,3}#{1,6}\s+"#,       // 标题
            #"^\s{0,3}>\s*"#,            // 引用
            #"^\s{0,3}[-*+]\s+"#,        // 无序列表
            #"^\s{0,3}\d+[.)]\s+"#,      // 有序列表
        ]
        for p in patterns {
            if let r = line.range(of: p, options: .regularExpression) {
                return r.upperBound
            }
        }
        return line.startIndex
    }

    private static func isFenceLine(_ line: String) -> Bool {
        line.range(of: #"^\s*(```|~~~)"#, options: .regularExpression) != nil
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        line.range(of: #"^\s*\|?[\s:|-]+\|?\s*$"#, options: .regularExpression) != nil
            && line.contains("-")
    }
}
