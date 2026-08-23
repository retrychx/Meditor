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
    ///
    /// 内容走内存（tab.content）：HTML 预览实际用 loadHTMLString + 合成 https
    /// base URL 渲染（CDN 脚本可用），不依赖磁盘文件——AI 写回/编辑后内容变化
    /// 立即反映在预览里，不用等保存落盘。reloadToken 兼作内容变化信号，
    /// WebPreviewView 按 (fileURL, reloadToken) 去重。
    @discardableResult
    func showHTML(fileURL: URL, content newContent: String) -> Bool {
        let normalized = fileURL.standardizedFileURL
        let current    = htmlFileURL?.standardizedFileURL
        var changed = false
        if language != .html       { language = .html }
        if mode != .html           { mode = .html;              changed = true }
        if current != normalized   { htmlFileURL = fileURL;     changed = true }
        if content != newContent   { content = newContent;      changed = true }
        if changed { reloadToken &+= 1 }
        return changed
    }

    /// 正在预览的 HTML 文件在磁盘上被更新后的强制刷新（外部修改/回滚等路径）。
    /// 常规内容变化已由 sync(from:) 通过 tab.content 驱动 reloadToken，无需落盘。
    /// 仅当确实在显示该文件时才触发，避免无谓刷新。
    func reloadHTML(url: URL) {
        guard mode == .html,
              htmlFileURL?.standardizedFileURL == url.standardizedFileURL else { return }
        reloadToken &+= 1
    }

    /// Sync preview content from the given tab.
    func sync(from tab: EditorTab) {
        let sid = PerformanceTracer.begin("SyncPreviewContent", log: PerformanceTracer.preview)
        defer { PerformanceTracer.end("SyncPreviewContent", log: PerformanceTracer.preview, id: sid) }
        if tab.language == .html {
            showHTML(fileURL: tab.url, content: tab.content)
        } else {
            showMarkdown(content: tab.content)
        }
    }
}
