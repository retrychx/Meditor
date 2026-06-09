import Foundation

struct ScrollSyncCommand: Equatable {
    var line: Int
    var nonce: Int

    static let idle = ScrollSyncCommand(line: -1, nonce: 0)

    func advanced(to line: Int) -> ScrollSyncCommand {
        ScrollSyncCommand(line: line, nonce: nonce &+ 1)
    }
}
