import Foundation
import Observation

// MARK: - TodoStore

/// 全局待办状态，由 AppState 持有，TodoMainView 和 TodoSidebarView 共享。
/// 所有磁盘 IO 均在后台线程执行，完成后回 MainActor 更新状态。
@MainActor
@Observable
final class TodoStore {

    // MARK: - State

    private(set) var todos: [TodoItem] = []
    private(set) var isLoading = false

    // MARK: - Scan

    /// 扫描工作区，完整刷新 todos 列表。
    func reload(rootURL: URL?) async {
        guard let root = rootURL else { todos = []; return }
        isLoading = true
        todos = await TodoScanner.scan(rootURL: root)
        isLoading = false
    }

    // MARK: - Toggle

    /// 切换 checkbox 状态，写回磁盘，并同步 `todos` 数组。
    /// - Returns: 成功返回 true；失败返回 false 并抛出（调用方处理错误提示）。
    func toggle(_ item: TodoItem) async throws {
        guard let idx = todos.firstIndex(where: { $0.id == item.id }) else { return }

        // 后台写磁盘
        try await Task.detached(priority: .userInitiated) {
            try TodoScanner.toggle(item: item)
        }.value

        // 主线程更新状态（翻转 isChecked）
        todos[idx] = TodoItem(
            id:        item.id,
            text:      item.text,
            isChecked: !item.isChecked,
            fileURL:   item.fileURL,
            lineIndex: item.lineIndex
        )
    }

    // MARK: - Add

    /// 追加新待办到指定文件末尾。
    /// - Returns: 写入后的完整文件内容（供调用方同步编辑器）。
    @discardableResult
    func addTodo(text: String, to fileURL: URL) async throws -> String {
        let line = "\n- [ ] \(text)"

        let newContent: String = try await Task.detached(priority: .userInitiated) {
            // 读失败必须向上抛（调用方展示错误）：以空串兜底再原子重写会把目标文件
            // 截断成只剩一行新 todo。仅文件不存在（首次创建）才允许以空串为基底。
            let existing: String
            if FileManager.default.fileExists(atPath: fileURL.path) {
                existing = try String(contentsOf: fileURL, encoding: .utf8)
            } else {
                existing = ""
            }
            let updated  = existing + line
            try updated.write(to: fileURL, atomically: true, encoding: .utf8)
            return updated
        }.value

        // 追加到本地列表（无需全量 reload，避免闪烁）
        let lineIndex = newContent.components(separatedBy: "\n").count - 1
        todos.append(TodoItem(
            id:        TodoItem.stableID(fileURL: fileURL, lineIndex: lineIndex),
            text:      text,
            isChecked: false,
            fileURL:   fileURL,
            lineIndex: lineIndex
        ))

        return newContent
    }
}
