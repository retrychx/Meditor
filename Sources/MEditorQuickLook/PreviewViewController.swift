import AppKit
import JavaScriptCore
import OSLog
import QuickLookUI
import UniformTypeIdentifiers
import WebKit

/// 扩展日志：log show --predicate 'subsystem == "com.meditor.app.QuickLook"'
private let qlLog = Logger(subsystem: "com.meditor.app.QuickLook", category: "preview")

/// Quick Look 预览控制器：Finder 选中 .md 按空格时，把 Markdown 渲染成 HTML 展示。
///
/// 技术选型（macOS 26 SDK 的约束）：
/// - SDK 里已没有 QLPreviewViewController（旧的视图式预览基类）。实测（qlmanage -p +
///   unified log）macOS 的 com.apple.quicklook.preview 扩展点仍按「视图式」处理主类
///   （建立 viewbridge、QLPreviewExtensionViewController 断言），纯 QLPreviewProvider
///   （数据式）主类收不到预览请求——所以主类是普通 NSViewController，内置 WKWebView。
/// - 渲染不走 WebView 里的 JS（模板那套要落盘 + 软链资源），而是直接用 JavaScriptCore
///   在 JSContext 里跑主 app 同一份 marked.min.js + highlight.min.js + ql-render.js，
///   产出静态 HTML 片段，再把主 app 同一份 themes.css/base.css 内联成完整文档，
///   一次性 loadHTMLString。无外部资源引用，沙箱内最稳。
///
/// 有意的取舍：
/// - 主题固定默认 github，不读用户设置：扩展是独立沙箱进程，读 app 的 settings
///   需要 App Group + 进程间同步，复杂度不值当。
/// - Markdown 里的相对路径图片不加载：沙箱只授予被预览文件本身的读权限，
///   主 app 靠自定义 scheme（meditor-asset）绕过，扩展不引入这套机制。
/// - mermaid 需要 DOM，扩展里降级为代码块显示。
@objc(MEditorQLPreviewViewController)
final class PreviewViewController: NSViewController, QLPreviewingController {

    private var webView: WKWebView?

    override func loadView() {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.setValue(false, forKey: "drawsBackground")
        self.webView = webView
        self.view = webView
    }

    // MARK: - QLPreviewingController

    /// 系统在主线程调用一次；渲染是同步快路径（marked 同步解析），直接做完再回调。
    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        qlLog.notice("preparePreviewOfFile: \(url.lastPathComponent, privacy: .public)")
        do {
            let html = try Self.renderHTML(forFileAt: url)
            qlLog.notice("render ok, html bytes=\(html.utf8.count)")
            webView?.loadHTMLString(html, baseURL: nil)
            handler(nil)
        } catch {
            qlLog.error("render failed: \(error.localizedDescription, privacy: .public)，退回纯文本")
            // 渲染失败不退空：WebView 显示等宽纯文本，QL 至少能看到源文件内容
            if let markdown = try? String(contentsOf: url, encoding: .utf8) {
                webView?.loadHTMLString(Self.plainTextHTML(markdown), baseURL: nil)
                handler(nil)
            } else {
                handler(error)
            }
        }
    }

    // MARK: - 渲染

    private enum RenderError: LocalizedError {
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
        // 样式内联——loadHTMLString 没有 base URL，引不了外部 css。
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
