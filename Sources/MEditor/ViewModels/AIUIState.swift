import Foundation
import Observation

/// AI assistant UI state — separated from AppState to keep AI concerns isolated.
@MainActor
@Observable
final class AIUIState {
    /// Current editor selection text, forwarded to the AI as context.
    var editorSelectedText: String = ""
    /// Current preview selection text (for preview-side inline edit).
    var previewSelectedText: String = ""
    /// 预览选区的视口位置（操作浮动条跟随选区摆放）；.zero = 无位置信息。
    var previewSelectedRect: CGRect = .zero
    /// 「问 AI」带入的引用选段，显示为输入框上方的引用卡片（独立于用户输入框文本）。
    var quotedContext: String? = nil
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

    /// 待消费的内联选区提示：AI 面板打开时自动带入该文本并预填输入框。
    var pendingSelectionPrompt: String? = nil

    func requestInsert(_ text: String) {
        editorInsertText = text
        editorInsertNonce += 1
    }

    func requestReplace(_ text: String) {
        editorReplaceText = text
        editorReplaceNonce += 1
    }

    /// 打开 AI 面板，并把选中文本预填到输入框。
    func openAssistantWithSelection(_ text: String) {
        pendingSelectionPrompt = text
        showingAssistant = true
    }
}
