import Foundation

/// 纯文本字面定位辅助：供内联编辑链路在「范围失效 / 锚点重定位」时安全地
/// 找回目标位置，绝不退化为全局替换或盲目取首个匹配。
extension String {

    /// `needle` 在全文恰好唯一出现时的字面范围；不出现或多次出现都返回 nil
    /// （多处相同文本无法确定目标，调用方应放弃而不是猜）。
    func uniqueLiteralRange(of needle: String) -> Range<String.Index>? {
        guard !needle.isEmpty,
              let first = range(of: needle, options: .literal) else { return nil }
        guard range(of: needle, options: .literal, range: first.upperBound..<endIndex) == nil
        else { return nil }
        return first
    }

    /// 全文中离 `anchor` 最近的一处 `needle` 字面匹配；无匹配返回 nil。
    /// 用于合并后的文档里重定位闪示锚点：原文选区位置附近的匹配优先，
    /// 避免相同段落存在时闪错位置。
    func literalRange(of needle: String, nearestTo anchor: String.Index) -> Range<String.Index>? {
        guard !needle.isEmpty else { return nil }
        let anchorOffset = distance(from: startIndex, to: anchor)
        var best: Range<String.Index>?
        var bestDistance = Int.max
        var searchStart = startIndex
        while let hit = range(of: needle, options: .literal, range: searchStart..<endIndex) {
            let d = abs(distance(from: startIndex, to: hit.lowerBound) - anchorOffset)
            if d < bestDistance {
                best = hit
                bestDistance = d
            }
            searchStart = hit.upperBound
        }
        return best
    }
}
