import Foundation
import Observation

/// A single open editor tab.
///
/// Implemented as `@Observable class` so that SwiftUI observation tracks
/// individual property access rather than the whole `AppState.openTabs`
/// array. The key win: typing text mutates `tab.content` on the class
/// reference — the `openTabs` array value does NOT change, so TabButton
/// views that only read `tab.name` / `tab.isModified` are never re-rendered.
/// @unchecked Sendable：tab 在后台保存/读取路径中与主线程共享引用；现有设计已按此约定
/// 使用（saveTab 在 detached 任务里读取内容快照），迁移 Swift 6 时显式标注该约定。
@Observable
final class EditorTab: Identifiable, @unchecked Sendable {
    let id: UUID
    var url: URL
    var content: String
    /// Monotonic revision used by SwiftUI equality gates without comparing the
    /// full content string on every render.
    var contentRevision: Int
    var language: EditorLanguage
    var isModified: Bool
    var awaitingInitialContent: Bool

    var name: String { url.lastPathComponent }
    var iconName: String {
        language == .markdown ? "doc.text" : "doc.richtext"
    }

    init(
        id: UUID = UUID(),
        url: URL,
        content: String,
        language: EditorLanguage,
        contentRevision: Int = 0,
        isModified: Bool = false,
        awaitingInitialContent: Bool = false
    ) {
        self.id = id
        self.url = url
        self.content = content
        self.language = language
        self.contentRevision = contentRevision
        self.isModified = isModified
        self.awaitingInitialContent = awaitingInitialContent
    }
}
