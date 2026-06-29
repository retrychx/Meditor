import Foundation

// MARK: - Preview forwarding

extension AppState {

    var previewContent: String             { previewManager.content }
    var previewContentRevision: Int        { previewManager.contentRevision }
    var previewLanguage: EditorLanguage    { previewManager.language }
    var previewMode: PreviewMode           { previewManager.mode }
    var previewHTMLFileURL: URL?           { previewManager.htmlFileURL }
    var previewReloadToken: Int            { previewManager.reloadToken }
    var previewExporter: PreviewExporter   { previewManager.exporter }
    var previewFindController: PreviewFindController { previewManager.findController }

    @discardableResult
    func clearPreview() -> Bool { previewManager.clear() }

    @discardableResult
    func showMarkdownPreview(content: String) -> Bool { previewManager.showMarkdown(content: content) }

    @discardableResult
    func showHTMLPreview(fileURL: URL) -> Bool { previewManager.showHTML(fileURL: fileURL) }

    func syncPreviewContent(from tab: EditorTab) { previewManager.sync(from: tab) }

    /// 指定文件落盘后，若正在 HTML 预览该文件则强制重新加载（方案 A）。
    func reloadHTMLPreviewIfShowing(_ url: URL) { previewManager.reloadHTML(url: url) }
}
