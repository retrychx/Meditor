import Foundation
import JavaScriptCore

/// Markdown → HTML 离线渲染器（JavaScriptCore，无 DOM、无 WebView）。
///
/// 跑的是主 app 同一份 marked.min.js + highlight.min.js + ql-render.js，
/// 产出静态 HTML 片段，再把主 app 同一份 themes.css/base.css 内联成完整文档。
/// 预览本身由系统 QuickLookUI 渲染（见 PreviewProvider），扩展进程里没有 WebKit。
///
/// 有意的取舍：
/// - 主题固定默认 github，不读用户设置：扩展是独立沙箱进程，读 app 的 settings
///   需要 App Group + 进程间同步，复杂度不值当。
/// - Markdown 里的相对路径图片不加载：沙箱只授予被预览文件本身的读权限，
///   主 app 靠自定义 scheme（meditor-asset）绕过，扩展不引入这套机制。
/// - mermaid 需要 DOM，扩展里降级为代码块显示。
enum QLMarkdownRenderer {

    enum RenderError: LocalizedError {
        case fileUnreadable
        case resourceMissing(String)
        case jsFailed(String)

        var errorDescription: String? {
            switch self {
            case .fileUnreadable: return "无法读取 Markdown 文件"
            case .resourceMissing(let name): return "扩展资源缺失: \(name)"
            case .jsFailed(let msg): return "Markdown 渲染失败: \(msg)"
            }
        }
    }

    /// Markdown 文件 → 完整 HTML 文档（含内联样式）。
    static func renderHTML(forFileAt url: URL) throws -> String {
        guard let markdown = try? String(contentsOf: url, encoding: .utf8) else {
            throw RenderError.fileUnreadable
        }
        let bodyHTML = try renderBodyHTML(markdown: markdown)

        // 外壳与主 app 的 template.html 同构（<html class="theme-github"> + #content），
        // 样式内联——QLPreviewReply 的 HTML 数据不带 base URL，引不了外部 css。
        let themesCSS = try loadResourceString("Preview/css/themes.css")
        let baseCSS = try loadResourceString("Preview/css/base.css")
        return """
        <!DOCTYPE html>
        <html class="theme-github">
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>
        \(themesCSS)
        </style>
        <style>
        \(baseCSS)
        </style>
        </head>
        <body>
        <div id="content">\(bodyHTML)</div>
        </body>
        </html>
        """
    }

    /// 用 JavaScriptCore 跑主 app 同一份 marked/highlight + ql-render.js，产出正文 HTML 片段。
    static func renderBodyHTML(markdown: String) throws -> String {
        guard let context = JSContext() else {
            throw RenderError.jsFailed("JSContext 创建失败")
        }
        var jsException: String?
        context.exceptionHandler = { _, exception in
            jsException = exception?.toString()
        }

        // highlight.min.js 的 UMD 包直接引用 window；JSContext 里没有，
        // 指向全局对象即可（window === self === globalThis）
        context.evaluateScript("var window = this; var self = this;")

        // 顺序有依赖：marked → hljs → ql-render（驱动依赖前两者）
        for script in ["Preview/marked.min.js", "Preview/highlight.min.js", "ql-render.js"] {
            context.evaluateScript(try loadResourceString(script))
            if let jsException { throw RenderError.jsFailed("\(script): \(jsException)") }
        }

        guard let render = context.objectForKeyedSubscript("MEditorQL")?
            .objectForKeyedSubscript("render"),
            !render.isUndefined else {
            throw RenderError.jsFailed("MEditorQL.render 未定义")
        }
        guard let result = render.call(withArguments: [markdown]),
              let html = result.toString(),
              jsException == nil else {
            throw RenderError.jsFailed(jsException ?? "render 调用无返回值")
        }
        return html
    }

    /// 兜底纯文本页（等宽、保留换行）。
    static func plainTextHTML(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return """
        <!DOCTYPE html>
        <html><head><meta charset="UTF-8"></head>
        <body><pre style="font: 12px Menlo, monospace; padding: 16px; white-space: pre-wrap;">\(escaped)</pre></body>
        </html>
        """
    }

    /// 读 appex 包内资源（bundle.sh 组装时从主 app 拷贝过来的同一份文件）。
    static func loadResourceString(_ relativePath: String) throws -> String {
        guard let base = Bundle.main.resourceURL else {
            throw RenderError.resourceMissing("Resources")
        }
        let url = base.appendingPathComponent(relativePath)
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            throw RenderError.resourceMissing(relativePath)
        }
        return content
    }
}
