import Foundation
import Observation

/// Owns all preview-panel state and update logic.
///
/// AppState.syncPreviewContent(from:) delegates here. Views read preview state
/// through forwarding computed properties on AppState (unchanged API).
@MainActor
@Observable
final class PreviewManager {

    // MARK: - State

    var content: String = ""
    var contentRevision: Int = 0
    var language: EditorLanguage = .markdown
    var mode: PreviewMode = .empty {
        didSet {
            findController.activeMode = mode
            if mode == .empty { findController.close() }
        }
    }
    var htmlFileURL: URL?
    var reloadToken: Int = 0

    // MARK: - Sub-services

    let exporter = PreviewExporter()
    let findController = PreviewFindController()

    // MARK: - Actions

    /// Clear the preview panel. Returns true if any state changed.
    @discardableResult
    func clear() -> Bool {
        var changed = false
        if !content.isEmpty        { content = "";              changed = true }
        if htmlFileURL != nil      { htmlFileURL = nil;         changed = true }
        if mode != .empty          { mode = .empty;             changed = true }
        if changed { contentRevision &+= 1 }
        return changed
    }

    /// Show a rendered Markdown document. Returns true if any state changed.
    @discardableResult
    func showMarkdown(content newContent: String) -> Bool {
        var changed = false
        if htmlFileURL != nil          { htmlFileURL = nil;              changed = true }
        if language != .markdown       { language = .markdown }
        if content != newContent       { content = newContent;           changed = true }
        if mode != .markdown           { mode = .markdown;               changed = true }
        if changed { contentRevision &+= 1 }
        return changed
    }

    /// Show an HTML file preview. Returns true if any state changed.
    @discardableResult
    func showHTML(fileURL: URL) -> Bool {
        let normalized = fileURL.standardizedFileURL
        let current    = htmlFileURL?.standardizedFileURL
        var changed = false
        if !content.isEmpty        { content = "";              changed = true }
        if language != .html       { language = .html }
        if mode != .html           { mode = .html;              changed = true }
        if current != normalized   { htmlFileURL = fileURL; reloadToken &+= 1; changed = true }
        return changed
    }

    /// Sync preview content from the given tab.
    func sync(from tab: EditorTab) {
        let sid = PerformanceTracer.begin("SyncPreviewContent", log: PerformanceTracer.preview)
        defer { PerformanceTracer.end("SyncPreviewContent", log: PerformanceTracer.preview, id: sid) }
        if tab.language == .html {
            showHTML(fileURL: tab.url)
        } else {
            showMarkdown(content: tab.content)
        }
    }
}
