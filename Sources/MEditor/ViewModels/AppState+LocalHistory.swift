import Foundation

// MARK: - 本地历史快照（AppState 接线层）
//
// 存取逻辑在 LocalHistoryStore；这里负责把「保存落快照 / 启动清理 / 一键恢复」
// 接到 App 生命周期与 UI 反馈上。

extension AppState {

    /// 保存成功后的快照记录（TabManager.onDidWriteContent 回调）。后台线程执行，
    /// 失败只记日志——历史是兜底机制，不打断保存主流程。
    func recordHistorySnapshot(url: URL, content: String) {
        let store = historyStore
        Task.detached(priority: .utility) {
            do {
                try store.recordSnapshot(of: url, content: content)
            } catch {
                AppLog.error(.fileWrite(url, underlying: error), in: AppLog.file)
            }
        }
    }

    /// 启动时惰性清理过期/超量快照（AppState.init 调用一次）。
    func scheduleHistoryPrune() {
        let store = historyStore
        Task.detached(priority: .background) {
            store.pruneAll()
        }
    }

    /// 一键恢复某份快照：
    /// 1. 先给当前内容落一份快照（恢复本身可回退）；
    /// 2. 走 applyAIWriteBack —— 编辑器挂载时是可撤销的最小化替换（⌘Z 一步撤回），
    ///    未挂载时退回 tab 内容整体替换（标记为已修改，随后按自动保存策略落盘）；
    /// 3. toast 确认。
    func restoreHistorySnapshot(_ snapshot: HistorySnapshot, for tab: EditorTab) {
        let content: String
        do {
            content = try historyStore.readSnapshot(snapshot)
        } catch {
            setError(L("history.readFailed", error.localizedDescription))
            return
        }
        // 恢复前快照当前内容：写失败不阻断恢复（当前内容仍在内存/磁盘上）
        try? historyStore.recordSnapshot(of: tab.url, content: tab.content)
        applyAIWriteBack(tab.id, content: content)
        showToast(L("history.restored"), icon: "arrow.uturn.backward")
    }
}
