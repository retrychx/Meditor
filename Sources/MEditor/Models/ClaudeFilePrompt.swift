import Foundation

/// Claude Code 检测到新建文件时弹出的用户提示。
struct ClaudeFilePrompt: Identifiable, Equatable {
    let id = UUID()
    let fileURL: URL

    var fileName: String { fileURL.lastPathComponent }
    var directory: String {
        let dir = fileURL.deletingLastPathComponent().path
        // 缩短 home 路径显示
        let home = NSHomeDirectory()
        return dir.hasPrefix(home) ? "~" + dir.dropFirst(home.count) : dir
    }

    var onAccept:  () -> Void
    var onDismiss: () -> Void

    static func == (lhs: ClaudeFilePrompt, rhs: ClaudeFilePrompt) -> Bool {
        lhs.id == rhs.id
    }
}
