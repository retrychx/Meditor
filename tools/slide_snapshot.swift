import WebKit
import AppKit

// 放映模板截图工具：复刻 PresentationWindowController 的加载方式，
// 用离屏 WKWebView 渲染 template.html + MEditorSlides.boot(...)，逐页截图。
// 用法: swift tools/slide_snapshot.swift <theme> <outPrefix>

let theme = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "github"
let outPrefix = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "/tmp/slide"

// 与真实放映一致的典型内容：封面 / 列表 / 代码 / 表格+引用
let sampleSlides: [String] = [
    """
    # MEditor 产品演进路线

    从 Markdown 编辑器到 AI 文档工作台

    2026 年 8 月
    """,
    """
    ## 核心能力

    - **AI Agent**：多轮工具调用，直接读写工作区文档
    - 实时预览：marked.js + highlight.js + Mermaid
    - 双端同步：iCloud Drive 原地编辑
    - 局域网分享与一键发布

    > 定位：预览即文档，AI 是手。
    """,
    """
    ## 架构示例

    ```swift
    @MainActor
    @Observable
    final class DocumentStore {
        private(set) var text: String = ""
        private(set) var sandboxURL: URL? = nil

        func replaceContent(_ newContent: String) throws {
            guard let url = sandboxURL else { throw AgentContextError.noActiveDocument }
            try writeText(newContent, to: url)
            text = newContent
        }
    }
    ```
    """,
    """
    ## 版本对比

    | 维度 | 1.0 | 1.1 |
    |------|-----|-----|
    | 架构 | x86_64 | Universal |
    | iCloud | 不支持 | 原地编辑 |
    | 测试 | 548 | 555 |

    性能提升约 **40%**，内存占用下降 25%。
    """
]

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let templateURL = root.appendingPathComponent("Sources/MEditor/Resources/Presentation/template.html")

final class Delegate: NSObject, WKNavigationDelegate {
    var onFinish: (() -> Void)?
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { onFinish?() }
}

let config = WKWebViewConfiguration()
config.setURLSchemeHandler(MeditorAssetSchemeHandlerShim(), forURLScheme: "meditor-asset")
let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1280, height: 720), configuration: config)
let delegate = Delegate()
webView.navigationDelegate = delegate

// meditor-asset scheme 在本脚本里不需要真实文件，空响应即可
final class MeditorAssetSchemeHandlerShim: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        let resp = URLResponse(url: urlSchemeTask.request.url!, mimeType: "text/plain", expectedContentLength: 0, textEncodingName: nil)
        urlSchemeTask.didReceive(resp)
        urlSchemeTask.didFinish()
    }
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}

func jsonEncode(_ s: String) -> String {
    let data = try! JSONEncoder().encode(s)
    return String(data: data, encoding: .utf8)!
}

var slideIndex = 0

func shoot() {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
        webView.takeSnapshot(with: nil) { image, error in
            guard let image = image, let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else {
                print("snapshot failed: \(String(describing: error))"); exit(1)
            }
            let path = "\(outPrefix)-\(theme)-\(slideIndex + 1).png"
            try! png.write(to: URL(fileURLWithPath: path))
            print("wrote \(path)")
            slideIndex += 1
            if slideIndex < sampleSlides.count {
                webView.evaluateJavaScript("MEditorSlides.next()") { _, err in
                    if let err { print("next error: \(err)") }
                    shoot()
                }
            } else {
                exit(0)
            }
        }
    }
}

delegate.onFinish = {
    let payload = "{ slides: [\(sampleSlides.map(jsonEncode).joined(separator: ","))], theme: \"\(theme)\", baseHref: \"\" }"
    // 离屏 WebView 的 CSS transition 提交不可靠，截图前禁掉动画
    webView.evaluateJavaScript("""
        var st = document.createElement('style');
        st.textContent = '* { transition: none !important; }';
        document.head.appendChild(st);
        MEditorSlides.boot(\(payload));
    """) { _, err in
        if let err { print("boot error: \(err)"); exit(1) }
        shoot()
    }
}

webView.loadFileURL(templateURL, allowingReadAccessTo: root.appendingPathComponent("Sources/MEditor/Resources"))
app.run()
