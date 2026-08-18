import Foundation

// MARK: - 写确认 diff 预览（数据 + 构建）
//
// 设计取舍：
//   - diff 在写工具调 confirmFileWrite 之前预算好——此时写前内容最容易拿到
//    （tab 内存优先的 fileContentFull / currentDocument 就在手边，与
//     AgentRunCheckpoint.captureBeforeWrite 的取值取舍一致）。
//   - 复用 ParagraphDiffer 的段落级 diff；确认条 UI 只消费轻量 WriteDiffHunk，
//     不引入 DiffReview 的 accept/skip 状态机。
//   - 大小上限对齐 AgentRunCheckpoint 的 1MB 快照取舍：超大文件不算 diff，
//     确认条退化为只显示 summary（LCS 是 O(段落m×n)，大文件既慢也无展示价值）。

/// 一处段落级改动（由 ParagraphDiff 映射而来的轻量 Sendable 版本）。
struct WriteDiffHunk: Identifiable, Sendable {
    let id = UUID()
    /// 原文段落（空串 = 纯新增）
    let original: String
    /// 新文段落（空串 = 纯删除）
    let modified: String
}

/// 确认条可展示的 diff 内容。
enum WriteDiff: Sendable {
    /// 段落级改动（空数组 = 内容无实质变化）
    case hunks([WriteDiffHunk])
    /// 超过大小上限，不展示 diff（确认条退化为 summary + 提示文案）
    case tooLarge
    /// 写前内容不可得（如读盘失败），只展示 summary
    case unavailable
}

/// confirmFileWrite 的完整请求数据：path/summary + diff 预览。
struct FileWritePreview: Sendable {
    /// 展示用目标路径（解析后的文件路径或当前文档名）
    let path: String
    /// 一句话变更描述（如「写入 docs/a.md（约 120 行）」）
    let summary: String
    let diff: WriteDiff
}

/// 写前内容的来源形态（由工具层根据目标文件是否存在 / 是否可读判定）。
enum WriteBaseContent {
    /// 文件已存在，写前内容已知（调用方需经 fileContentFull 取，tab 内存优先）
    case existing(String)
    /// 全新文件（diff = 纯新增）
    case newFile
    /// 写前内容读取失败 / 目标不可解析
    case unavailable
}

/// 写确认 diff 预览的构建器（无状态纯函数，便于单测）。
enum WriteDiffPreviewBuilder {

    /// 单侧内容大小上限（1MB，与 AgentRunCheckpoint.maxSnapshotBytes 同取舍）。
    static let maxDiffBytes = 1_000_000
    /// 单侧段落数上限：LCS DP 表是 O(m×n)，双边各 2000 段约 32MB 内存，
    /// 再高算起来又慢又占内存，直接退化为 tooLarge。
    static let maxDiffParagraphs = 2000

    /// 用「写前内容 vs 写入内容」构建确认请求。
    static func make(path: String, summary: String,
                     base: WriteBaseContent, newContent: String) -> FileWritePreview {
        FileWritePreview(path: path, summary: summary, diff: diff(base: base, newContent: newContent))
    }

    private static func diff(base: WriteBaseContent, newContent: String) -> WriteDiff {
        let old: String
        switch base {
        case .unavailable:     return .unavailable
        case .newFile:         old = ""
        case .existing(let s): old = s
        }
        guard old.utf8.count <= maxDiffBytes, newContent.utf8.count <= maxDiffBytes else {
            return .tooLarge
        }
        // 段落数守卫先于 LCS：split 很便宜，先挡住会导致 DP 表爆炸的输入
        let origBlocks = ParagraphDiffer.splitParagraphs(old)
        let modfBlocks = ParagraphDiffer.splitParagraphs(newContent)
        guard origBlocks.count <= maxDiffParagraphs, modfBlocks.count <= maxDiffParagraphs else {
            return .tooLarge
        }
        let hunks = ParagraphDiffer.diff(original: old, modified: newContent).map {
            WriteDiffHunk(original: $0.original, modified: $0.modified)
        }
        return .hunks(hunks)
    }
}
