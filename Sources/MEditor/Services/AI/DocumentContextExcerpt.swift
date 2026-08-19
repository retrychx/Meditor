import Foundation

// MARK: - DocumentContextExcerpt

/// 自动附带文档的上下文预算截取。
///
/// 发送聊天时当前文档作为默认上下文注入 system prompt。文档在预算内时整篇注入；
/// 超预算时不再整篇硬截断，而是保留「首部 + 光标附近段落 + 尾部」，中间以省略
/// 标记衔接——模型既看到文档结构（首尾），又拿到用户正在编辑的位置（光标段）。
/// token 估算复用 AIConversation.estimateTokens（与上下文预算/截断横幅同一口径）。
enum DocumentContextExcerpt {

    /// 默认预算（估算 token）。约等于原 8000 字符硬截断的中英文混合量级。
    static let defaultMaxTokens = 3_000

    /// 段间省略标记（注入 system prompt，给模型看的结构提示）。
    static let ellipsis = "[...]"

    /// 预算内返回原文；超预算返回「首部 20% + 光标附近 60% + 尾部 20%」的摘录。
    /// - Parameter cursorLine: 1-based 光标行号（AppState.cursorLine）；nil 时围绕
    ///   文档中段截取。
    static func excerpt(content: String, cursorLine: Int?, maxTokens: Int = defaultMaxTokens) -> String {
        guard AIConversation.estimateTokens(content) > maxTokens else { return content }

        let paragraphs = content.components(separatedBy: "\n\n")
        guard paragraphs.count > 1 else {
            // 单段落超长文档：段落级截取无从谈起，退化为「首 + 光标行附近 + 尾」行级截取
            return capToBudget(
                lineLevelExcerpt(content: content, cursorLine: cursorLine, maxTokens: maxTokens),
                maxTokens: maxTokens)
        }

        let cursorPara = paragraphIndex(forLine: cursorLine, in: paragraphs) ?? paragraphs.count / 2
        let headBudget = maxTokens / 5
        let tailBudget = maxTokens / 5
        let midBudget  = maxTokens * 3 / 5

        // 首部：从头累加段落直到预算（至少保留一段）
        var headEnd = 0
        var tokens = 0
        while headEnd < paragraphs.count {
            let t = AIConversation.estimateTokens(paragraphs[headEnd])
            if headEnd > 0, tokens + t > headBudget { break }
            tokens += t; headEnd += 1
        }

        // 尾部：从尾向前累加（与首部不重叠；至少保留一段）
        var tailStart = paragraphs.count
        tokens = 0
        while tailStart > headEnd {
            let t = AIConversation.estimateTokens(paragraphs[tailStart - 1])
            if tailStart < paragraphs.count, tokens + t > tailBudget { break }
            tokens += t; tailStart -= 1
        }

        // 中段：光标段落向两侧交替扩展（限制在首/尾区间之间）
        var midStart = cursorPara, midEnd = cursorPara + 1
        if cursorPara < headEnd || cursorPara >= tailStart {
            // 光标已被首/尾覆盖，中段为空
            midStart = max(headEnd, min(cursorPara, tailStart))
            midEnd = midStart
        } else {
            tokens = AIConversation.estimateTokens(paragraphs[cursorPara])
            var expandUp = true
            var canUp = midStart - 1 >= headEnd
            var canDown = midEnd < tailStart
            while canUp || canDown {
                if expandUp {
                    if canUp {
                        let t = AIConversation.estimateTokens(paragraphs[midStart - 1])
                        if tokens + t <= midBudget { midStart -= 1; tokens += t } else { canUp = false }
                    }
                } else {
                    if canDown {
                        let t = AIConversation.estimateTokens(paragraphs[midEnd])
                        if tokens + t <= midBudget { midEnd += 1; tokens += t } else { canDown = false }
                    }
                }
                canUp = canUp && midStart - 1 >= headEnd
                canDown = canDown && midEnd < tailStart
                expandUp.toggle()
            }
        }

        // 超长光标段（单段就超中段预算）：行级截取光标附近
        var middleParts = paragraphs[midStart..<midEnd].map { $0 }
        if midEnd == midStart + 1,
           AIConversation.estimateTokens(middleParts[0]) > midBudget {
            let lineInPara = lineOffsetWithinParagraph(cursorLine: cursorLine, paragraphIndex: midStart, paragraphs: paragraphs)
            middleParts = [lineLevelExcerpt(content: middleParts[0], cursorLine: lineInPara + 1, maxTokens: midBudget)]
        }

        // 首/尾第一段单独超预算时（首段数万字符的文档），段级保留会整段注入、
        // 预算失效——退化为对该段的行级截取（与超长光标段同一思路）
        var headText = paragraphs[0..<headEnd].joined(separator: "\n\n")
        if headEnd == 1, AIConversation.estimateTokens(headText) > headBudget {
            headText = lineLevelExcerpt(content: headText, cursorLine: 1, maxTokens: headBudget)
        }
        var tailText = paragraphs[tailStart...].joined(separator: "\n\n")
        if tailStart == paragraphs.count - 1, AIConversation.estimateTokens(tailText) > tailBudget {
            let tailLineCount = tailText.components(separatedBy: "\n").count
            tailText = lineLevelExcerpt(content: tailText, cursorLine: tailLineCount, maxTokens: tailBudget)
        }

        // 拼接：区间之间插省略标记
        var parts: [String] = []
        if headEnd > 0 { parts.append(headText) }
        if midStart > headEnd { parts.append(ellipsis) }
        if midEnd > midStart { parts.append(middleParts.joined(separator: "\n\n")) }
        if tailStart > midEnd { parts.append(ellipsis) }
        if tailStart < paragraphs.count { parts.append(tailText) }
        return capToBudget(parts.joined(separator: "\n\n"), maxTokens: maxTokens)
    }

    // MARK: - Private

    /// 总量兜底校验：拼接结果仍超预算（单段/单行内部即超预算、省略标记顶破
    /// 预算等）时按字符保留首 60% + 尾 40%。estimateTokens 单字符至多 2/3
    /// token（CJK），按字符数封顶必在预算内。
    private static func capToBudget(_ text: String, maxTokens: Int) -> String {
        guard AIConversation.estimateTokens(text) > maxTokens else { return text }
        let headChars = maxTokens * 3 / 5
        let tailChars = maxTokens * 2 / 5
        guard text.count > headChars + tailChars else { return text }
        return String(text.prefix(headChars)) + "\n" + ellipsis + "\n" + String(text.suffix(tailChars))
    }

    /// 1-based 行号 → 段落索引（段落间空行计入行数）。
    private static func paragraphIndex(forLine cursorLine: Int?, in paragraphs: [String]) -> Int? {
        guard let cursorLine, cursorLine > 0 else { return nil }
        var line = 1   // 当前段落的起始行（1-based）
        for (index, para) in paragraphs.enumerated() {
            let lineCount = para.components(separatedBy: "\n").count
            if cursorLine <= line + lineCount - 1 { return index }
            line += lineCount + 1   // +1：段间空行
        }
        return paragraphs.isEmpty ? nil : paragraphs.count - 1
    }

    /// 光标行在段落内的 0-based 偏移（用于超长单段的行级截取）。
    private static func lineOffsetWithinParagraph(cursorLine: Int?, paragraphIndex: Int, paragraphs: [String]) -> Int {
        guard let cursorLine, cursorLine > 0 else { return 0 }
        var line = 1
        for (index, para) in paragraphs.enumerated() where index < paragraphIndex {
            line += para.components(separatedBy: "\n").count + 1
        }
        return max(0, cursorLine - line)
    }

    /// 行级截取（单段落/超长段落的兜底）：首 20% + 光标行附近 60% + 尾 20%。
    private static func lineLevelExcerpt(content: String, cursorLine: Int?, maxTokens: Int) -> String {
        let lines = content.components(separatedBy: "\n")
        let cursorIdx = max(0, min((cursorLine ?? 1) - 1, lines.count - 1))
        let headBudget = maxTokens / 5
        let tailBudget = maxTokens / 5
        let midBudget  = maxTokens * 3 / 5

        var headEnd = 0
        var tokens = 0
        while headEnd < lines.count {
            let t = AIConversation.estimateTokens(lines[headEnd])
            if headEnd > 0, tokens + t > headBudget { break }
            tokens += t; headEnd += 1
        }
        var tailStart = lines.count
        tokens = 0
        while tailStart > headEnd {
            let t = AIConversation.estimateTokens(lines[tailStart - 1])
            if tailStart < lines.count, tokens + t > tailBudget { break }
            tokens += t; tailStart -= 1
        }
        var midStart = cursorIdx, midEnd = cursorIdx + 1
        tokens = AIConversation.estimateTokens(lines[cursorIdx])
        var expandUp = true
        var canUp = midStart - 1 >= headEnd
        var canDown = midEnd < tailStart
        while canUp || canDown {
            if expandUp {
                if canUp {
                    let t = AIConversation.estimateTokens(lines[midStart - 1])
                    if tokens + t <= midBudget { midStart -= 1; tokens += t } else { canUp = false }
                }
            } else {
                if canDown {
                    let t = AIConversation.estimateTokens(lines[midEnd])
                    if tokens + t <= midBudget { midEnd += 1; tokens += t } else { canDown = false }
                }
            }
            canUp = canUp && midStart - 1 >= headEnd
            canDown = canDown && midEnd < tailStart
            expandUp.toggle()
        }

        var parts: [String] = []
        if headEnd > 0 { parts.append(lines[0..<headEnd].joined(separator: "\n")) }
        if midStart > headEnd { parts.append(ellipsis) }
        if midEnd > midStart { parts.append(lines[midStart..<midEnd].joined(separator: "\n")) }
        if tailStart > midEnd { parts.append(ellipsis) }
        if tailStart < lines.count { parts.append(lines[tailStart...].joined(separator: "\n")) }
        return parts.joined(separator: "\n")
    }
}
