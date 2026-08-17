import Foundation

struct ScrollSyncCommand: Equatable {
    var line: Int
    var nonce: Int
    /// true = 滚动后把光标落到目标行并闪烁高亮（全局搜索跳转）；
    /// false = 纯滚动（预览→编辑器同步，不动光标）。
    var selectLine: Bool = false

    static let idle = ScrollSyncCommand(line: -1, nonce: 0)

    func advanced(to line: Int, select: Bool = false) -> ScrollSyncCommand {
        ScrollSyncCommand(line: line, nonce: nonce &+ 1, selectLine: select)
    }
}
