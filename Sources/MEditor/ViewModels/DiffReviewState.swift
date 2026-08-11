import Foundation
import Observation

// MARK: - DiffReviewState

@MainActor
@Observable
final class DiffReviewState {

    // MARK: Presentation

    var isPresented  = false
    var isLoading    = false
    var loadingLabel = ""

    // MARK: Streaming phase

    /// True while AI is generating (before paragraph diff is computed).
    var isStreaming      = false
    /// Accumulated streaming text shown live in the right pane.
    var streamedContent = ""
    /// Human-readable label of the action being performed (e.g. "改写").
    var streamingAction = ""
    /// Held so `dismiss()` can cancel an in-flight stream.
    var activeStreamTask: Task<Void, Never>? = nil
    /// 当前正在运行的 AgentRunner（流式/微调）——dismiss 时取消。
    var activeRunner: AgentRunner? = nil

    /// 回调失效防护（generation token）：beginStreaming / dismiss 各递增一次。
    /// 发起方启动 run 后捕获该值，迟到的 onChunk/onComplete 必须经
    /// writeStreamedContent / commitStreamWithModified(_:generation:onFinalize:) 写入，
    /// dismiss（或新一轮流式）之后在途回调不得再把 diffs / streamedContent 写回。
    private(set) var streamGeneration = 0

    // MARK: Content

    var originalContent: String = ""
    var modifiedContent: String = ""
    var diffs: [ParagraphDiff] = []
    var mode: DiffReviewMode = .markdownVsMarkdown

    // MARK: 连续微调（refine）

    /// 「继续调整」输入框文本（DiffModeBar 绑定）。
    var refineInput: String = ""
    /// 最近一次 AI 生成的选区替换文本——微调时作为新的输入文本。
    var lastGeneratedText: String = ""
    /// 由发起方（inline edit）注入的微调执行闭包；nil = 不显示微调入口。
    var onRefine: ((String) -> Void)?

    // MARK: Derived

    var pendingCount: Int { diffs.filter { $0.status == .pending }.count }
    var hasPending:   Bool { pendingCount > 0 }

    // MARK: Write-back

    /// Called with the final merged content once all diffs are resolved.
    /// - markdownVsMarkdown: receives the merged Markdown string.
    /// - markdownVsHTML: receives `modifiedContent` (the generated HTML).
    var onFinalize: ((String) -> Void)?

    // MARK: 快照过期防护（写回时重定位）

    /// 写回那一刻读取当前文档内容的闭包（由发起方注入，如行内编辑）。
    /// 非 nil 时 finalize 以当前内容为起点合并，避免过期快照回滚用户在
    /// AI 运行期间的手动编辑；nil 时保持原有的快照索引合并（其他链路不变）。
    var currentContentProvider: (() -> String?)?
    /// 目标段落在当前内容中无法定位（用户已改动目标区域）时的回调：
    /// 发起方负责提示用户；此时绝不写回，审阅界面保留，由用户放弃本次结果。
    var onRebaseConflict: (() -> Void)?

    // MARK: Streaming entry point

    /// Activate diff mode immediately and start streaming phase.
    /// Call `appendStreamChunk(_:)` for each chunk, then `commitStream(onFinalize:)` when done.
    func beginStreaming(original: String, actionLabel: String) {
        streamGeneration += 1
        originalContent = original
        streamedContent = ""
        streamingAction = actionLabel
        modifiedContent = ""
        diffs           = []
        isStreaming     = true
        onFinalize      = nil
        onRefine        = nil      // 连续微调入口由发起方在调用后重新注入
        currentContentProvider = nil   // 快照过期防护闭包由发起方在调用后重新注入
        onRebaseConflict     = nil
        lastGeneratedText = ""
        isPresented     = true
    }

    func appendStreamChunk(_ chunk: String) {
        streamedContent += chunk
    }

    /// 带 generation 校验的流式写入：token 失效（dismiss / 新一轮 beginStreaming）时
    /// 丢弃迟到的 chunk，不写回 streamedContent。
    func writeStreamedContent(_ content: String, generation: Int) {
        guard generation == streamGeneration, isStreaming else { return }
        streamedContent = content
    }

    /// Switch from streaming phase to paragraph-diff review phase.
    func commitStream(onFinalize: @escaping (String) -> Void) {
        isStreaming     = false
        modifiedContent = streamedContent
        self.onFinalize = onFinalize
        diffs = ParagraphDiffer.diff(original: originalContent, modified: streamedContent)
    }

    /// Like commitStream but uses an externally-computed modified string
    /// (e.g. full document with AI result spliced in).
    func commitStreamWithModified(_ modified: String, onFinalize: @escaping (String) -> Void) {
        isStreaming     = false
        modifiedContent = modified
        self.onFinalize = onFinalize
        diffs = ParagraphDiffer.diff(original: originalContent, modified: modified)
    }

    /// 带 generation 校验的 commit：dismiss 后迟到的 onComplete 不得复活 diffs，
    /// 也不得触发 onFinalize 写回文档。返回是否真正提交（false = token 已失效，写入被丢弃）。
    @discardableResult
    func commitStreamWithModified(_ modified: String, generation: Int, onFinalize: @escaping (String) -> Void) -> Bool {
        guard generation == streamGeneration, isStreaming else { return false }
        commitStreamWithModified(modified, onFinalize: onFinalize)
        return true
    }

    // MARK: Present

    func present(
        original: String,
        modified: String,
        mode: DiffReviewMode = .markdownVsMarkdown,
        selectedOriginal: String? = nil,
        selectedModified: String? = nil,
        onFinalize: ((String) -> Void)? = nil
    ) {
        self.originalContent = original
        self.modifiedContent = modified
        self.mode            = mode
        self.onFinalize      = onFinalize
        self.isStreaming      = false
        self.streamedContent  = ""
        self.streamingAction  = ""
        self.onRefine         = nil
        self.currentContentProvider = nil
        self.onRebaseConflict     = nil
        self.lastGeneratedText = ""
        guard mode == .markdownVsMarkdown else { self.diffs = []; self.isPresented = true; return }

        if let selOrig = selectedOriginal, let selMod = selectedModified {
            // Diff only the selected region
            let selDiffs = ParagraphDiffer.diff(original: selOrig, modified: selMod)
            let fullOrigBlocks = ParagraphDiffer.splitParagraphs(original)
            let fullModBlocks  = ParagraphDiffer.splitParagraphs(modified)
            let selOrigBlocks  = ParagraphDiffer.splitParagraphs(selOrig)
            let selModBlocks   = ParagraphDiffer.splitParagraphs(selMod)
            // Find where selected region starts in full document
            let origOffset = fullOrigBlocks.firstIndex(where: { selOrigBlocks.first == $0 }) ?? 0
            let modOffset  = fullModBlocks.firstIndex(where: { selModBlocks.first == $0 }) ?? 0
            self.diffs = selDiffs.map { d in
                ParagraphDiff(
                    id: d.id,
                    originalIndex: d.originalIndex >= 0 ? d.originalIndex + origOffset : -1,
                    modifiedIndex: d.modifiedIndex >= 0 ? d.modifiedIndex + modOffset  : -1,
                    original: d.original,
                    modified: d.modified,
                    status: d.status
                )
            }
        } else {
            self.diffs = ParagraphDiffer.diff(original: original, modified: modified)
        }
        self.isPresented = true
    }

    // MARK: Diff actions

    func accept(_ id: UUID) {
        guard let i = diffs.firstIndex(where: { $0.id == id }) else { return }
        diffs[i].status = .accepted
        checkAutoFinish()
    }

    func skip(_ id: UUID) {
        guard let i = diffs.firstIndex(where: { $0.id == id }) else { return }
        diffs[i].status = .skipped
        checkAutoFinish()
    }

    func acceptAll() {
        for i in diffs.indices { diffs[i].status = .accepted }
        finalize()
    }

    func skipAll() {
        for i in diffs.indices { diffs[i].status = .skipped }
        dismiss()
    }

    // MARK: Merged content

    func mergedContent() -> String {
        guard mode == .markdownVsMarkdown else { return modifiedContent }

        var blocks = ParagraphDiffer.splitParagraphs(originalContent)

        // Apply accepted substitutions/deletions in reverse index order
        // so that earlier-index operations don't shift later indices.
        let sorted = diffs
            .filter { $0.status == .accepted }
            .sorted { $0.originalIndex > $1.originalIndex }

        var additions: [(modfIndex: Int, text: String)] = []

        for diff in sorted {
            if diff.originalIndex >= 0 {
                if diff.modified.isEmpty {
                    // Deletion
                    if diff.originalIndex < blocks.count {
                        blocks.remove(at: diff.originalIndex)
                    }
                } else {
                    // Substitution
                    if diff.originalIndex < blocks.count {
                        blocks[diff.originalIndex] = diff.modified
                    }
                }
            } else if !diff.modified.isEmpty {
                // Pure addition — collect and insert after all deletions/substitutions
                additions.append((modfIndex: diff.modifiedIndex, text: diff.modified))
            }
        }

        // Insert additions at their modified-side positions (best-effort)
        for add in additions.sorted(by: { $0.modfIndex < $1.modfIndex }) {
            let idx = min(add.modfIndex, blocks.count)
            blocks.insert(add.text, at: idx)
        }

        return blocks.joined(separator: "\n\n")
    }

    /// 基于「写回那一刻的当前文档内容」合并 accepted diffs（快照过期防护，方案 2）。
    ///
    /// AI 运行期间用户可能继续手动编辑，diffs 的 originalIndex 基于触发时的过期
    /// 快照，直接按索引合并会回滚用户编辑。这里改用快照段落文本在当前内容中重定位
    /// 目标段落：
    /// - 目标段落原样存在且可唯一确定 → 以当前内容为起点替换/删除/插入，用户在
    ///   他处的编辑保留；
    /// - 目标段落找不到、或多处相同文本无法确定是哪一段 → 返回 nil，调用方绝不写回。
    func mergedContent(rebasingTo current: String) -> String? {
        guard mode == .markdownVsMarkdown else { return modifiedContent }
        // 当前内容未被改动：走原有的索引合并（精确路径）
        guard current != originalContent else { return mergedContent() }

        let accepted = diffs.filter { $0.status == .accepted }
        guard !accepted.isEmpty else { return current }

        var blocks = ParagraphDiffer.splitParagraphs(current)

        // 第一遍：重定位所有替换/删除的目标段落——先全部定位成功再动手，避免半合并状态
        var targets: [(diff: ParagraphDiff, index: Int)] = []
        for diff in accepted where diff.originalIndex >= 0 {
            guard let idx = Self.locate(diff.original, preferredIndex: diff.originalIndex, in: blocks)
            else { return nil }
            targets.append((diff, idx))
        }
        // 两个 diff 命中同一段落 = 定位歧义，拒绝
        guard Set(targets.map { $0.index }).count == targets.count else { return nil }

        // 第二遍：倒序应用替换/删除（与 mergedContent() 同理，避免索引偏移）
        for (diff, idx) in targets.sorted(by: { $0.index > $1.index }) {
            if diff.modified.isEmpty {
                blocks.remove(at: idx)          // 删除
            } else {
                blocks[idx] = diff.modified     // 替换
            }
        }

        // 纯新增：锚定到 modified 侧前一个已落位的段落（可能是替换后的新文本或未改动
        // 的原文；additions 按 modifiedIndex 升序处理，前面的新增此时已在 blocks 里），
        // 唯一定位后插入其后；锚点找不到或有歧义同样拒绝。
        let modfBlocks = ParagraphDiffer.splitParagraphs(modifiedContent)
        let additions = accepted
            .filter { $0.originalIndex < 0 && !$0.modified.isEmpty }
            .sorted { $0.modifiedIndex < $1.modifiedIndex }
        for add in additions {
            guard add.modifiedIndex > 0 else {
                blocks.insert(add.modified, at: 0)
                continue
            }
            var anchored = false
            var j = add.modifiedIndex - 1
            while j >= 0 {
                let matches = blocks.indices.filter { blocks[$0] == modfBlocks[j] }
                if matches.count > 1 { return nil }     // 锚点歧义，拒绝
                if matches.count == 1 {
                    blocks.insert(add.modified, at: matches[0] + 1)
                    anchored = true
                    break
                }
                j -= 1   // 该段落未被接受（不在当前内容中），继续向前找锚点
            }
            guard anchored else { return nil }
        }

        return blocks.joined(separator: "\n\n")
    }

    /// 在当前内容段落中定位快照段落：优先原位（索引未因编辑偏移）；否则要求全文
    /// 唯一匹配——多处相同文本无法确定目标是哪一段，返回 nil 拒绝（绝不误改）。
    private static func locate(_ text: String, preferredIndex: Int, in blocks: [String]) -> Int? {
        if preferredIndex < blocks.count, blocks[preferredIndex] == text { return preferredIndex }
        let matches = blocks.indices.filter { blocks[$0] == text }
        return matches.count == 1 ? matches[0] : nil
    }

    // MARK: Dismiss

    func dismiss() {
        streamGeneration += 1   // 使在途回调的 token 立即失效（迟到的 onChunk/onComplete 被丢弃）
        activeStreamTask?.cancel()
        activeStreamTask = nil
        activeRunner?.cancel()
        activeRunner = nil
        isPresented      = false
        isLoading        = false
        isStreaming      = false
        loadingLabel     = ""
        streamedContent  = ""
        streamingAction  = ""
        diffs            = []
        originalContent  = ""
        modifiedContent  = ""
        onFinalize       = nil
        onRefine         = nil
        currentContentProvider = nil
        onRebaseConflict     = nil
        lastGeneratedText = ""
        refineInput      = ""
    }

    // MARK: Private

    private func checkAutoFinish() {
        if !hasPending { finalize() }
    }

    private func finalize() {
        // 快照过期防护：发起方注入了当前内容读取闭包时，以写回那一刻的文档为起点
        // 重定位合并；目标段落已被用户改动（无法定位）时绝不覆盖——提示并保留审阅
        // 界面，由用户放弃本次结果（dismiss / skipAll）。
        if mode == .markdownVsMarkdown, let current = currentContentProvider?() {
            guard let merged = mergedContent(rebasingTo: current) else {
                onRebaseConflict?()
                return
            }
            onFinalize?(merged)
            dismiss()
            return
        }
        let content = mode == .markdownVsMarkdown ? mergedContent() : modifiedContent
        onFinalize?(content)
        dismiss()
    }
}
