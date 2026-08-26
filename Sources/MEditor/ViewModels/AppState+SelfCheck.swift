import Foundation

// MARK: - Agent 写后自检的「一键修复」入口

extension AppState {

    /// 自检报告条的「一键修复」：定位到目标文档（必要时打开 tab），复用 /fix
    /// 链路（静态诊断 → prompt → 流式 diff 审阅 → 用户确认写回）。
    /// 只处理 fixable 列表所在文档；reportOnly（死链/缺图）不自动改，
    /// 留在报告里由用户人工确认。
    func runAgentSelfCheckFix(_ report: AgentWriteSelfCheck.Report) {
        guard let target = report.fixTarget,
              let tab = focusSelfCheckTarget(url: target),
              let command = AISlashCommandRegistry.command(id: "fix") else { return }
        // tab 刚打开内容可能还在异步加载：退到读盘，与 AppStateDocumentAdapter 同一 fallback
        let content = tab.awaitingInitialContent
            ? ((try? String(contentsOf: target, encoding: .utf8)) ?? tab.content)
            : tab.content
        // 与诊断面板同一口径：超 /fix 执行器整篇上限则不发起（按钮在 UI 层已禁用，这里兜底）
        guard content.count <= SlashAICommandExecutor.maxDocumentChars else {
            showToast(L("slash.documentTooLarge"), icon: "exclamationmark.triangle")
            return
        }
        agentWriteSelfCheck.dismissReport()
        SlashAICommandExecutor.run(
            command: command, argument: "", documentText: content,
            insertionLocation: 0, state: self, settings: AppSettings.shared)
    }

    /// 定位修复目标 tab：已打开则切换选中，未打开（且在磁盘上）则打开。
    /// 返回目标 tab；文件不可打开时返回 nil。
    @discardableResult
    func focusSelfCheckTarget(url: URL) -> EditorTab? {
        if let tab = openTabs.first(where: {
            $0.url.standardizedFileURL == url.standardizedFileURL
        }) {
            selectedTabID = tab.id
            return tab
        }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        openFile(FileItem(url: url, isDirectory: false))
        return openTabs.first { $0.url.standardizedFileURL == url.standardizedFileURL }
    }
}
