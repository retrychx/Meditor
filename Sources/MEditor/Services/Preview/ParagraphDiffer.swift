import Foundation

// MARK: - ParagraphDiffer

enum ParagraphDiffer {

    // MARK: Public API

    /// Splits `content` into paragraph blocks (separated by blank lines).
    static func splitParagraphs(_ content: String) -> [String] {
        content
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Returns only the changed paragraphs between `original` and `modified`.
    /// Uses index-aligned comparison for paragraphs at the same position,
    /// then LCS for remainder, merging adjacent delete+add pairs into substitutions.
    static func diff(original: String, modified: String) -> [ParagraphDiff] {
        let origBlocks = splitParagraphs(original)
        let modfBlocks = splitParagraphs(modified)

        guard !origBlocks.isEmpty || !modfBlocks.isEmpty else { return [] }

        let edits = lcsEdits(origBlocks, modfBlocks)
        return buildDiffs(edits: edits, orig: origBlocks, modf: modfBlocks)
    }

    // MARK: LCS

    private struct Edit {
        enum Kind { case unchanged, deleted, inserted }
        let kind: Kind
        let origIndex: Int   // -1 if inserted
        let modfIndex: Int   // -1 if deleted
    }

    private static func lcsEdits(_ a: [String], _ b: [String]) -> [Edit] {
        let m = a.count, n = b.count
        // DP table
        // stride 而非 1...m：一侧为空（全新增 / 全删除）时 1...0 会直接崩溃
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in stride(from: 1, through: m, by: 1) {
            for j in stride(from: 1, through: n, by: 1) {
                dp[i][j] = a[i-1] == b[j-1] ? dp[i-1][j-1] + 1
                                              : max(dp[i-1][j], dp[i][j-1])
            }
        }
        // Backtrack
        var edits: [Edit] = []
        var i = m, j = n
        while i > 0 || j > 0 {
            if i > 0 && j > 0 && a[i-1] == b[j-1] {
                edits.append(Edit(kind: .unchanged, origIndex: i-1, modfIndex: j-1))
                i -= 1; j -= 1
            } else if j > 0 && (i == 0 || dp[i][j-1] >= dp[i-1][j]) {
                edits.append(Edit(kind: .inserted, origIndex: -1, modfIndex: j-1))
                j -= 1
            } else {
                edits.append(Edit(kind: .deleted, origIndex: i-1, modfIndex: -1))
                i -= 1
            }
        }
        return edits.reversed()
    }

    private static func buildDiffs(edits: [Edit], orig: [String], modf: [String]) -> [ParagraphDiff] {
        var result: [ParagraphDiff] = []
        var pendingDel: Edit? = nil

        for edit in edits {
            switch edit.kind {
            case .unchanged:
                if let del = pendingDel {
                    // Orphan deletion — no adjacent insertion to pair with
                    result.append(ParagraphDiff(
                        id: UUID(),
                        originalIndex: del.origIndex,
                        modifiedIndex: -1,
                        original: orig[del.origIndex],
                        modified: "",
                        status: .pending
                    ))
                    pendingDel = nil
                }

            case .deleted:
                if let del = pendingDel {
                    result.append(ParagraphDiff(
                        id: UUID(),
                        originalIndex: del.origIndex,
                        modifiedIndex: -1,
                        original: orig[del.origIndex],
                        modified: "",
                        status: .pending
                    ))
                }
                pendingDel = edit

            case .inserted:
                if let del = pendingDel {
                    // Pair deletion + insertion → substitution
                    result.append(ParagraphDiff(
                        id: UUID(),
                        originalIndex: del.origIndex,
                        modifiedIndex: edit.modfIndex,
                        original: orig[del.origIndex],
                        modified: modf[edit.modfIndex],
                        status: .pending
                    ))
                    pendingDel = nil
                } else {
                    result.append(ParagraphDiff(
                        id: UUID(),
                        originalIndex: -1,
                        modifiedIndex: edit.modfIndex,
                        original: "",
                        modified: modf[edit.modfIndex],
                        status: .pending
                    ))
                }
            }
        }

        // Flush trailing deletion
        if let del = pendingDel {
            result.append(ParagraphDiff(
                id: UUID(),
                originalIndex: del.origIndex,
                modifiedIndex: -1,
                original: orig[del.origIndex],
                modified: "",
                status: .pending
            ))
        }

        return result
    }
}
