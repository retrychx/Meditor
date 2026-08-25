import Foundation

/// 内联编辑共享流式执行管线（编辑器圈选 InlineEditBar / 预览圈选
/// PreviewInlineEditBar 共用）：
/// - beginStreaming 打开 diff 视图并注入快照过期防护（写回时以当前文档重定位合并）；
/// - AgentRunner 注册到 diffReview.activeRunner：dismiss 才能取消运行，bar 销毁后
///   runner 由 diffReview 强持有，不会在途中被释放；
/// - generation token：dismiss / 新一轮流式后迟到的 onChunk / onComplete 写入被丢弃；
/// - 完成后 commit 进入段落审阅，接受后统一走 applyAIWriteBack 写回
///   （可撤销最小化替换、预览同步、isModified 与防抖保存均在其内部处理）。
///
/// 两侧仅 splice（AI 结果 → 全文）与收尾钩子不同，故抽为无状态静态入口 +
/// 闭包参数，而非引入新的有状态控制器。
@MainActor
enum InlineEditSession {

    /// 发起一次内联编辑运行。
    /// - Parameters:
    ///   - splice: 把 AI 生成的选区替换文本拼回全文（两侧的定位方式不同：
    ///     编辑器侧用 NSRange，预览侧用 SourceTextMapper 映射出的源码范围）。
    ///   - useTools: 微调等自由指令改写不带工具（纯文本改写，省 token）。
    ///   - onFinalize: 写回完成后的附加动作（如预览侧闪示改动位置），
    ///     参数为（合并后全文, AI 生成文本）。
    ///   - onSettled: onComplete 收尾时调用（如编辑器侧复位 loading 态）。
    static func run(
        state: AppState,
        settings: AppSettings,
        systemPrompt: String,
        userMessage: String,
        fullContent: String,
        actionLabel: String,
        splice: @escaping (String) -> String,
        useTools: Bool = true,
        onFinalize: ((String, String) -> Void)? = nil,
        onSettled: (() -> Void)? = nil
    ) {
        // 流式落笔：立即打开 diff 视图，AI 边生成边流入右栏
        state.diffReview.beginStreaming(original: fullContent, actionLabel: actionLabel)

        let runner = AgentRunner()
        state.diffReview.activeRunner = runner

        // 快照过期防护：AI 运行期间用户可能继续编辑——写回时以当前文档为起点
        // 重定位合并；目标段落已被改动则拒绝覆盖并提示，由用户放弃本次结果
        state.diffReview.currentContentProvider = { [weak state] in state?.selectedTab?.content }
        state.diffReview.onRebaseConflict = { [weak state] in
            state?.showToast(L("ai.inline.targetLost"),
                             icon: "exclamationmark.triangle")
        }
        // 捕获 generation token：dismiss / 新一轮流式后在途回调写入被丢弃
        let streamGen = state.diffReview.streamGeneration

        runner.onChunk = { [weak state] chunk in
            guard let state, !chunk.isEmpty else { return }
            state.diffReview.writeStreamedContent(splice(chunk), generation: streamGen)
        }

        runner.onComplete = { [weak state, weak runner] in
            guard let state else { return }
            defer { onSettled?() }
            // 只在自己的 runner 仍注册时释放引用（避免清掉后一轮运行的注册）
            if let runner, state.diffReview.activeRunner === runner {
                state.diffReview.activeRunner = nil
            }
            if let err = runner?.error {
                state.diffReview.dismiss()
                state.showToast(err, icon: "exclamationmark.triangle")
                return
            }
            let finalText = runner?.finalText ?? ""
            guard !finalText.isEmpty else {
                state.diffReview.dismiss()
                state.showToast(L("ai.inline.emptyResponse"), icon: "exclamationmark.triangle")
                return
            }
            let modified = splice(finalText)
            // token 失效（dismiss / 新一轮流式）时 commit 被丢弃，lastGeneratedText 也不写回
            let committed = state.diffReview.commitStreamWithModified(modified, generation: streamGen) { merged in
                if let tab = state.selectedTab {
                    state.applyAIWriteBack(tab.id, content: merged)
                }
                onFinalize?(merged, finalText)
            }
            if committed {
                // 连续微调输入：committed 的生成文本作为下一轮微调的输入
                state.diffReview.lastGeneratedText = finalText
            }
        }

        runner.run(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            tools: useTools ? BuiltinAgentTools.all : [],
            config: AIConfig.current(settings, scene: .inline),
            context: AgentContext.make(appState: state)
        )
    }
}
