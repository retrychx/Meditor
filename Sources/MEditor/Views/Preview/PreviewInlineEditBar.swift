import SwiftUI

/// Floating action strip shown at the bottom of the preview when text is selected.
/// Triggers AI inline edit then opens the diff-review overlay instead of a sheet.
@MainActor
struct PreviewInlineEditBar: View {
    @Environment(AppState.self)    private var state
    @Environment(AppSettings.self) private var settings

    let selectedText: String
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 2) {
            // 内容感知：按选中内容类型只显示最相关的 3-4 个操作（与编辑器内联栏一致）
            ForEach(contextualActions) { action in
                actionButton(action)
            }

            // 问 AI 入口（预览栏此前缺失）
            Divider()
                .frame(height: 14)
                .padding(.horizontal, 4)
            askAIButton
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        .padding(.bottom, 12)
    }

    // MARK: - 内容感知动作列表

    /// 根据选中内容类型返回最相关的 AI 操作，最多 4 个（与 InlineEditBar 一致）。
    private var contextualActions: [InlineEditAction] {
        let t = selectedText.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("```") || t.hasPrefix("    ") {
            return [.explainCode, .addComments, .condense]
        }
        if t.hasPrefix("#") {
            return [.expandSection, .rewrite]
        }
        let lines = t.components(separatedBy: "\n").filter { !$0.isEmpty }
        let isListLike = lines.count >= 2 && lines.prefix(3).allSatisfy {
            $0.hasPrefix("- ") || $0.hasPrefix("* ") || $0.hasPrefix("+ ") ||
            $0.range(of: #"^\d+\. "#, options: .regularExpression) != nil
        }
        if isListLike {
            return [.organizeList, .expand, .condense]
        }
        return [.rewrite, .expand, .condense, .translate]
    }

    private func actionButton(_ action: InlineEditAction) -> some View {
        Button { triggerAction(action) } label: {
            HStack(spacing: 4) {
                Image(systemName: action.icon)
                    .font(.system(size: 10, weight: .medium))
                Text(action.displayName)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.05), in: Capsule())
        }
        .buttonStyle(.plain)
        .help(action.displayName)
    }

    /// 把选中文本带入 AI 面板，开启对话。
    private var askAIButton: some View {
        Button {
            guard !selectedText.isEmpty else { return }
            state.openAssistantWithSelection(selectedText)
            onDismiss?()
        } label: {
            HStack(spacing: 4) {
                AIAssistantOrb(size: 12)
                Text(L("ai.askAI"))
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(AIBrand.blue)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(AIBrand.blue.opacity(0.09), in: Capsule())
        }
        .buttonStyle(.plain)
        .help(L("ai.askAIHint"))
    }

    // MARK: - Action

    private func triggerAction(_ action: InlineEditAction) {
        guard !selectedText.isEmpty else { return }
        guard state.pluginManager.isBuiltinEnabled(BuiltinSkills.ID.inlineEditor) else {
            state.showToast(L("ai.error.notConfigured"), icon: "exclamationmark.triangle")
            return
        }
        let fullContent = state.selectedTab?.content ?? selectedText
        // 渲染选区映射回源码范围（剥掉 **、##、- 等语法后匹配，
        // 命中时向两侧吞掉紧邻的行内标记）。映射失败不乱改文档：
        // 提示用户从编辑器圈选，而不是拿 AI 结果整篇替换。
        guard let sourceRange = SourceTextMapper.sourceRange(
            ofPlainSelection: selectedText, in: fullContent
        ) else {
            state.showToast(L("ai.inline.mapFailed"), icon: "exclamationmark.triangle")
            onDismiss?()
            return
        }

        // 流式落笔：立即打开 diff 视图，AI 边生成边流入右栏
        state.diffReview.beginStreaming(original: fullContent, actionLabel: action.displayName)

        // 连续微调入口：对最近一次生成结果按自由指令迭代（"再短一点"…）
        state.diffReview.onRefine = { [weak state] instruction in
            guard let state else { return }
            Self.runRefinement(state: state, settings: settings, instruction: instruction,
                               fullContent: fullContent, sourceRange: sourceRange)
        }

        // 系统 prompt = 内置 inlineEditor skill + 用户插件附加（与编辑器链路一致）
        var systemPrompt = BuiltinSkills.inlineEditor.content
        let extra = state.pluginManager.userSkillsPrompt()
        if !extra.isEmpty { systemPrompt += "\n\n---\n\n# 附加技能\n\n" + extra }
        let userMsg = action.userInstruction(for: selectedText, document: fullContent)

        PreviewInlineEditFlow.runEdit(
            state: state, settings: settings,
            systemPrompt: systemPrompt, userMessage: userMsg,
            fullContent: fullContent, sourceRange: sourceRange, useTools: true
        )
        onDismiss?()
    }

    /// 连续微调：以上一次生成结果为输入，按自由指令再跑一轮，流式更新 diff。
    private static func runRefinement(
        state: AppState,
        settings: AppSettings,
        instruction: String,
        fullContent: String,
        sourceRange: Range<String.Index>
    ) {
        let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let previous = state.diffReview.lastGeneratedText
        guard !trimmed.isEmpty, !previous.isEmpty else { return }

        state.diffReview.beginStreaming(original: fullContent, actionLabel: L("ai.inline.adjust"))
        // beginStreaming 会清空微调入口，重新注入以便继续迭代
        state.diffReview.onRefine = { [weak state] next in
            guard let state else { return }
            Self.runRefinement(state: state, settings: settings, instruction: next,
                               fullContent: fullContent, sourceRange: sourceRange)
        }

        let systemPrompt = """
        你是文本优化助手。严格按照用户的修改指令改写给定文本，只输出改写后的文本本身，\
        不要输出解释、前言或引号。保持原文的 Markdown 格式约定。
        """
        let userMsg = "待修改文本：\n\n\(previous)\n\n修改指令：\(trimmed)"

        PreviewInlineEditFlow.runEdit(
            state: state, settings: settings,
            systemPrompt: systemPrompt, userMessage: userMsg,
            fullContent: fullContent, sourceRange: sourceRange, useTools: false
        )
    }
}


// MARK: - 流式执行器（首轮与微调共用）

/// 预览圈选 → AI 编辑的执行管线：AgentRunner 流式输出实时写入 diff 右栏
/// （流式落笔），完成后进入段落审阅；接受后写回文档并闪示改动位置（改哪亮哪）。
@MainActor
private enum PreviewInlineEditFlow {
    static func runEdit(
        state: AppState,
        settings: AppSettings,
        systemPrompt: String,
        userMessage: String,
        fullContent: String,
        sourceRange: Range<String.Index>,
        useTools: Bool
    ) {
        let r = AgentRunner()
        state.diffReview.activeRunner = r
        // 快照过期防护：AI 运行期间用户可能继续编辑——写回时以当前文档为起点
        // 重定位合并；目标段落已被改动则拒绝覆盖并提示，由用户放弃本次结果
        state.diffReview.currentContentProvider = { [weak state] in state?.selectedTab?.content }
        state.diffReview.onRebaseConflict = { [weak state] in
            state?.showToast(L("ai.inline.targetLost"),
                             icon: "exclamationmark.triangle")
        }
        // 捕获 generation token：dismiss / 新一轮流式后在途回调写入被丢弃
        let streamGen = state.diffReview.streamGeneration

        r.onChunk = { [weak state] fullText in
            guard let state, !fullText.isEmpty else { return }
            state.diffReview.writeStreamedContent(
                fullContent.replacingCharacters(in: sourceRange, with: fullText),
                generation: streamGen
            )
        }
        r.onComplete = { [weak state, weak r] in
            guard let state else { return }
            // 只在自己的 runner 仍注册时释放引用（避免清掉后一轮运行的注册）
            if let runner = r, state.diffReview.activeRunner === runner {
                state.diffReview.activeRunner = nil
            }
            if let err = r?.error {
                state.diffReview.dismiss()
                state.showToast(err, icon: "exclamationmark.triangle")
                return
            }
            let finalText = r?.finalText ?? ""
            guard !finalText.isEmpty else {
                state.diffReview.dismiss()
                state.showToast(L("ai.inline.emptyResponse"), icon: "exclamationmark.triangle")
                return
            }
            let modified = fullContent.replacingCharacters(in: sourceRange, with: finalText)
            // token 失效（dismiss / 新一轮流式）时 commit 被丢弃，lastGeneratedText 也不写回
            let committed = state.diffReview.commitStreamWithModified(modified, generation: streamGen) { merged in
                if let tab = state.selectedTab {
                    // 走 updateTabContent：同步预览 + 标 isModified（否则防抖保存会漏掉），
                    // 预览重渲染后 flashPreviewChange 的脉冲才能落到新 DOM 上。
                    state.updateTabContent(tab.id, content: merged)
                    state.scheduleDebounceSave()
                }
                // sourceRange 基于触发时的快照字符串；重定位合并后 merged 已是另一个
                // 字符串，过期索引用上去是越界风险。改为在 merged 中按 AI 生成文本
                // 重新定位闪示锚点，找不到则放弃本次闪示。
                if let flashRange = merged.range(of: finalText, options: .literal) {
                    state.flashPreviewChange(sourceRange: flashRange, in: merged)
                }
            }
            if committed {
                state.diffReview.lastGeneratedText = finalText
            }
        }
        r.run(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            tools: useTools ? BuiltinAgentTools.all : [],
            config: AIConfig.current(settings, scene: .inline),
            context: AgentContext.make(appState: state)
        )
    }
}
