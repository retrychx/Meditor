import Foundation

/// 演讲模式导出：把分页后的 Markdown 渲染成**单文件、自包含**的演讲 HTML。
///
/// 复用 bundle 内 Presentation/Preview 的静态资源（template.html/slides.js/slides.css
/// + themes.css/marked.min.js/highlight.min.js），全部内联进一个 HTML：
/// 浏览器双击打开即可放映，不依赖 app bundle。
/// slides/theme/baseHref 以 JSON 内联，页面加载后自动调用 `MEditorSlides.boot(...)`。
enum PresentationExporter {

    /// 生成自包含演讲 HTML；资源缺失或 JSON 编码失败时返回 nil。
    /// - Parameters:
    ///   - slides: 分页后的 Markdown 片段（见 `SlideSplitter`）。
    ///   - theme: 当前预览主题，决定 `<html>` 的 `theme-X` class。
    ///   - baseHref: 源文档目录的 file:// URL（带尾斜杠），供相对路径图片在浏览器中解析。
    static func makeHTML(slides: [String], theme: PreviewTheme, baseHref: String) -> String? {
        guard let root = PresentationResourceLocator.resourcesRoot() else { return nil }
        return makeHTML(slides: slides, theme: theme, baseHref: baseHref, presentationRoot: root)
    }

    /// 资源目录可注入的版本（测试用）。Preview 共享资源取 Presentation 的兄弟目录。
    static func makeHTML(slides: [String], theme: PreviewTheme, baseHref: String, presentationRoot: URL) -> String? {
        let previewRoot = presentationRoot.deletingLastPathComponent()
            .appendingPathComponent("Preview", isDirectory: true)

        func read(_ name: String, from root: URL) -> String? {
            try? String(contentsOf: root.appendingPathComponent(name), encoding: .utf8)
        }

        guard let template = read("template.html", from: presentationRoot),
              let slidesCSS = read("slides.css", from: presentationRoot),
              let slidesJS = read("slides.js", from: presentationRoot),
              let themesCSS = read("css/themes.css", from: previewRoot),
              let markedJS = read("marked.min.js", from: previewRoot),
              let highlightJS = read("highlight.min.js", from: previewRoot) else {
            return nil
        }

        // boot 参数格式与放映窗口注入的一致（见 PresentationWindowController.bootScript）
        let payload: [String: Any] = [
            "slides": slides,
            "theme": theme.rawValue,
            "baseHref": baseHref,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }

        // 外链资源原位替换为内联 <style>/<script>；boot 调用追加在 body 末尾，
        // 保证 #stage/#indicator 已存在于 DOM。
        return template
            .replacingOccurrences(of: "class=\"theme-github\"",
                                  with: "class=\"theme-\(theme.rawValue)\"")
            .replacingOccurrences(of: "<link rel=\"stylesheet\" href=\"../Preview/css/themes.css\">",
                                  with: "<style>\n\(themesCSS)\n</style>")
            .replacingOccurrences(of: "<link rel=\"stylesheet\" href=\"slides.css\">",
                                  with: "<style>\n\(slidesCSS)\n</style>")
            .replacingOccurrences(of: "<script src=\"../Preview/marked.min.js\"></script>",
                                  with: "<script>\n\(markedJS)\n</script>")
            .replacingOccurrences(of: "<script src=\"../Preview/highlight.min.js\"></script>",
                                  with: "<script>\n\(highlightJS)\n</script>")
            .replacingOccurrences(of: "<script src=\"slides.js\"></script>",
                                  with: "<script>\n\(slidesJS)\n</script>")
            .replacingOccurrences(of: "</body>",
                                  with: "<script>\nwindow.MEditorSlides && window.MEditorSlides.boot(\(json));\n</script>\n</body>")
    }
}
