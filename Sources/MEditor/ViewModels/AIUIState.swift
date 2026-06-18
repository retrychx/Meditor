import Foundation
import Observation

/// AI assistant UI state — separated from AppState to keep AI concerns isolated.
@MainActor
@Observable
final class AIUIState {
    /// Current editor selection text, forwarded to the AI as context.
    var editorSelectedText: String = ""
    /// Text to insert at the current caret position (driven by AI panel).
    var editorInsertText: String = ""
    /// Monotonic nonce so the same text can be inserted more than once.
    var editorInsertNonce: Int = 0
    /// Controls whether the AI assistant panel is visible.
    var showingAssistant: Bool = false

    /// Saved NSRange from the moment InlineEdit was triggered (before focus loss).
    var pendingReplaceRange: NSRange? = nil
    /// Text to replace the pendingReplaceRange with.
    var editorReplaceText: String = ""
    /// Monotonic nonce so the same text can be replaced more than once.
    var editorReplaceNonce: Int = 0

    func requestInsert(_ text: String) {
        editorInsertText = text
        editorInsertNonce += 1
    }

    func requestReplace(_ text: String) {
        editorReplaceText = text
        editorReplaceNonce += 1
    }
}
