import Foundation

// MARK: - ParagraphTargeting

/// Markdown 段落定位：以空行（\n\n）为段落边界，给定 UTF-16 偏移找出所在段落。
///
/// 供斜杠命令（/polish、/table 等）解析「当前段落」：命令删除后光标落在
/// 段间空行时，向前取最近的非空段落（与旧 /improve 取「光标前最后一段」一致）。
enum ParagraphTargeting {

    /// 返回 `utf16Offset` 所在段落的范围；偏移落在空白段（如命令刚被删除的空行）
    /// 时返回其之前最近的非空段落；文档为空或无有效段落时返回 nil。
    static func paragraphRange(at utf16Offset: Int, in text: String) -> Range<String.Index>? {
        guard !text.isEmpty,
              let pos = Range(NSRange(location: utf16Offset, length: 0), in: text)?.lowerBound
        else { return nil }

        var lastNonEmpty: Range<String.Index>? = nil
        var segStart = text.startIndex
        while segStart < text.endIndex {
            let segEnd = text.range(of: "\n\n", range: segStart..<text.endIndex)?.lowerBound
                ?? text.endIndex
            let seg = segStart..<segEnd
            let isEmpty = text[seg].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            // pos 落在段内或紧接段尾（\n\n 之前）时归属该段
            if seg.contains(pos) || pos == segEnd {
                return isEmpty ? lastNonEmpty : seg
            }
            if !isEmpty { lastNonEmpty = seg }
            guard let next = text.index(segEnd, offsetBy: 2, limitedBy: text.endIndex),
                  next > segStart else { break }
            segStart = next
        }
        // pos 在文档末尾的段间空白上：取最后非空段
        return lastNonEmpty
    }

    /// 选区所在段落（选区起点定位；选区必然落在非空文本上，不做空白回退）。
    static func paragraphRange(containing nsRange: NSRange, in text: String) -> Range<String.Index>? {
        guard Range(nsRange, in: text) != nil else { return nil }
        return paragraphRange(at: nsRange.location, in: text)
    }
}
