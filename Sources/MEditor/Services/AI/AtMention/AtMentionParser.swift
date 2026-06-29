import Foundation
import OSLog

// MARK: - AtMentionParser

enum AtMentionParser {

    // MARK: - Candidate generation

    @MainActor
    static func candidates(
        query: String,
        allFiles: [FileItem],
        rootURL: URL?,
        currentDocumentURL: URL?
    ) -> [AtMentionCandidate] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)

        // ── 内建关键词 ─────────────────────────────────────────
        var builtins: [AtMentionCandidate] = []
        if let url = currentDocumentURL {
            let c = AtMentionCandidate(kind: .currentDocument, relPath: url.lastPathComponent)
            if q.isEmpty || fuzzyScore(query: q, in: "current") > 0
                        || fuzzyScore(query: q, in: url.lastPathComponent.lowercased()) > 0 {
                builtins.append(c)
            }
        }
        if q.isEmpty || fuzzyScore(query: q, in: "workspace") > 0 {
            builtins.append(AtMentionCandidate(kind: .workspace, relPath: "workspace"))
        }

        // ── 预计算根路径，避免在循环内重复 standardizedFileURL ─────
        //    standardizedFileURL 是系统调用，per-file 开销显著
        let rootPath: String? = rootURL.map { r in
            var p = r.path
            if !p.hasSuffix("/") { p += "/" }  // 保证前缀匹配不会越界
            return p
        }

        // ── 文件/目录候选：一次 pass 完成打分 + 深度预计算 ──────────
        struct Scored {
            let candidate: AtMentionCandidate
            let score: Int
            let depth: Int   // 预计算，避免 sort comparator 内重复 filter
        }

        var scored: [Scored] = allFiles.compactMap { item in
            // 直接用 item.url.path（FileTreeManager 保证 URL 已为绝对路径）
            let urlPath = item.url.path
            let relPath: String
            if let root = rootPath, urlPath.hasPrefix(root) {
                relPath = String(urlPath.dropFirst(root.count))
            } else {
                relPath = item.name
            }

            let kind: AtMentionKind = item.isDirectory ? .directory(url: item.url) : .file(url: item.url)
            let candidate = AtMentionCandidate(kind: kind, relPath: relPath)

            // 深度：'/' 的个数（relPath 里每一层 dir 贡献一个 /）
            let depth = relPath.lazy.filter { $0 == "/" }.count

            if q.isEmpty { return Scored(candidate: candidate, score: 0, depth: depth) }

            // 精确文件名匹配优先
            let nameLower = item.name.lowercased()
            if nameLower == q {
                return Scored(candidate: candidate, score: 10000, depth: depth)
            }

            // 对「文件名」和「相对路径」各打一次分，取较高分
            let nameScore = fuzzyScore(query: q, in: nameLower)
            // 只有文件名打分不够时才跑完整路径打分（短路优化）
            let pathScore: Int
            if nameScore > 60 {
                pathScore = nameScore   // 文件名已经非常匹配，跳过路径打分
            } else {
                pathScore = fuzzyScore(query: q, in: relPath.lowercased())
            }
            let best = max(nameScore, pathScore)
            guard best > 10 else { return nil }
            return Scored(candidate: candidate, score: best, depth: depth)
        }

        if !q.isEmpty {
            scored.sort { a, b in
                if a.score != b.score { return a.score > b.score }
                return a.depth < b.depth      // 预计算的 depth，不再 filter
            }
        } else {
            scored.sort { a, b in
                if a.depth != b.depth { return a.depth < b.depth }
                return a.candidate.relPath < b.candidate.relPath
            }
        }

        let fileCandidates = scored.prefix(40).map(\.candidate)
        return builtins + fileCandidates
    }

    // MARK: - Fuzzy scorer
    //
    // Subsequence match — O(|query| + |haystack|)
    // 加分：路径段边界 +30，文件名首字符额外 +10，连续命中 +5，基础 +2
    // 惩罚：跳过字符 -1/个
    // 返回 0 = 不匹配

    static func fuzzyScore(query: String, in haystack: String) -> Int {
        guard !query.isEmpty, !haystack.isEmpty else { return 0 }

        // 用 UTF-8 码点操作，比 Array<Character> 快 ~2×（避免 Unicode 分簇）
        let qBytes = Array(query.utf8)
        let hBytes = Array(haystack.utf8)
        let qCount = qBytes.count
        let hCount = hBytes.count

        var qi = 0
        var score = 0
        var lastMatchIdx = -1

        for hi in 0..<hCount {
            guard qi < qCount else { break }
            guard hBytes[hi] == qBytes[qi] else { continue }

            var bonus = 0
            if hi == 0 {
                bonus += 30
            } else {
                let prev = hBytes[hi - 1]
                // 路径段边界：/ . _ - 或前一字符是大写字母（camelCase）
                if prev == 47 || prev == 46 || prev == 95 || prev == 45 {  // / . _ -
                    bonus += 30
                } else if prev >= 65 && prev <= 90 {  // 前字符大写 → 当前字符是边界
                    bonus += 30
                }
                // 文件名首字符（前一字符是 /）
                if prev == 47 { bonus += 10 }
            }
            // 连续命中
            if lastMatchIdx == hi - 1 { bonus += 5 }
            score += bonus + 2
            // 跳跃惩罚
            if lastMatchIdx >= 0 { score -= (hi - lastMatchIdx - 1) }

            lastMatchIdx = hi
            qi += 1
        }

        return qi == qCount ? score : 0
    }

    // MARK: - Token extraction from plain text

    static func extractMentionTexts(from text: String) -> [String] {
        let pattern = #"@([^\s@,;:!?'"(){}\[\]]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range(at: 1)) }
    }
}
