import Foundation

/// 代表 Markdown 文件中的一个 checkbox 条目。
struct TodoItem: Identifiable {
    let id: UUID
    var text: String
    var isChecked: Bool
    let fileURL: URL
    let lineIndex: Int
}
