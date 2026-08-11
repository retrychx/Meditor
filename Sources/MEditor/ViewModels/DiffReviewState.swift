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
        lastGeneratedText = ""
        refineInput      = ""
    }

    // MARK: Private

    private func checkAutoFinish() {
        if !hasPending { finalize() }
    }

    private func finalize() {
        let content = mode == .markdownVsMarkdown ? mergedContent() : modifiedContent
        onFinalize?(content)
        dismiss()
    }
}
