import Foundation

// MARK: - PatchEngine
// 无状态纯函数 — 既可独立单测，也可被 AgentContext / AgentDocumentAdapter 复用。

enum PatchEngine {

    // MARK: - Apply patch (三级降级)

    /// 三级降级匹配：字面 → 统一换行 → 去行尾空白
    /// 返回 (更新后文本, 替换次数)；count == 0 表示未找到匹配
    static func apply(
        to original: String,
        find: String,
        replace: String,
        all: Bool
    ) -> (updated: String, count: Int) {
        let candidates: [(String, String)] = [
            (original, find),
            (
                original.replacingOccurrences(of: "\r\n", with: "\n"),
                find.replacingOccurrences(of: "\r\n", with: "\n")
            ),
            (normalizeWSLines(original), normalizeWSLines(find))
        ]

        for (idx, (haystack, needle)) in candidates.enumerated() {
            if all {
                let replaced = haystack.replacingOccurrences(of: needle, with: replace)
                guard replaced != haystack else { continue }
                let count = haystack.components(separatedBy: needle).count - 1
                // 尽量保留原始换行风格
                let out = idx == 0
                    ? replaced
                    : original.replacingOccurrences(of: find, with: replace)
                return (out, count)
            } else {
                guard let range = haystack.range(of: needle, options: .literal) else { continue }
                if idx == 0 {
                    var tmp = original
                    tmp.replaceSubrange(range, with: replace)
                    return (tmp, 1)
                } else {
                    // 归一化后匹配成功：尝试在 original 上做字面替换
                    if let origRange = original.range(of: find, options: .literal) {
                        var tmp = original
                        tmp.replaceSubrange(origRange, with: replace)
                        return (tmp, 1)
                    }
                    var tmp = haystack
                    tmp.replaceSubrange(range, with: replace)
                    return (tmp, 1)
                }
            }
        }
        return (original, 0)
    }

    // MARK: - Nearby context（供 AI 自我纠正）

    /// 找不到匹配时，返回文件中最接近的行，让 AI 可见并自我纠正
    static func nearbyContext(in text: String, around find: String) -> String {
        let keyword = find
            .components(separatedBy: "\n")
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? ""
        guard !keyword.isEmpty else { return "(无法生成上下文：find 文本为空)" }

        let lines = text.components(separatedBy: "\n")
        let lower = keyword.lowercased()

        if let matchIdx = lines.indices.first(where: { lines[$0].lowercased().contains(lower) }) {
            let start = max(0, matchIdx - 2)
            let end   = min(lines.count - 1, matchIdx + 2)
            let ctx   = lines[start...end].enumerated()
                .map { "L\(start + $0.offset + 1): \($0.element)" }
                .joined(separator: "\n")
            return "文件中最接近的内容（L\(matchIdx + 1) 附近）：\n\(ctx)"
        }
        return "文件中未找到包含「\(keyword.prefix(40))」的行，请重新 read_document 确认内容。"
    }

    // MARK: - Normalization

    /// 去掉每行行尾空白并统一换行符
    static func normalizeWSLines(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .map { line -> String in
                var s = line
                while s.last == " " || s.last == "\t" { s.removeLast() }
                return s
            }
            .joined(separator: "\n")
    }
}
