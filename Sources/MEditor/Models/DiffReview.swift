import Foundation

// MARK: - DiffStatus

enum DiffStatus: Equatable {
    case pending
    case accepted
    case skipped

    var jsString: String {
        switch self {
        case .pending:  return "pending"
        case .accepted: return "accepted"
        case .skipped:  return "skipped"
        }
    }
}

// MARK: - ParagraphDiff

/// Represents a single changed paragraph between original and modified content.
struct ParagraphDiff: Identifiable {
    let id: UUID
    /// Index in the original content's paragraph array. -1 = pure addition.
    let originalIndex: Int
    /// Index in the modified content's paragraph array. -1 = pure deletion.
    let modifiedIndex: Int
    /// Original paragraph text (empty when the paragraph is purely added).
    let original: String
    /// Modified paragraph text (empty when the paragraph is purely deleted).
    let modified: String
    var status: DiffStatus
}

// MARK: - DiffReviewMode

enum DiffReviewMode {
    /// Both panes render Markdown; paragraph-level diff + write-back to source.
    case markdownVsMarkdown
    /// Left pane renders Markdown, right pane renders raw HTML (Beautify flow).
    case markdownVsHTML
}
