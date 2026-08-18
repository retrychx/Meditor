import Foundation
import OSLog
import QuickLookUI
import UniformTypeIdentifiers

private let providerLog = Logger(subsystem: "com.meditor.app.QuickLook", category: "provider")

/// 数据式预览：扩展只产出 HTML 数据，由系统 QuickLookUI 自己的 WebView 渲染。
///
/// 为什么从视图式（NSViewController + WKWebView）切过来：
/// macOS 26 上 app extension 由 launchd 直接拉起，RunningBoard 不把它当 app 管理，
/// WKWebView 的 Networking 子进程一启动就失去断言退出（日志：Network Process 0 crash /
/// "target process does not exist"），页面永远加载不出来。数据式把渲染交还给系统进程，
/// 扩展里根本没有 WebKit，绕开整个问题。
@objc(MEditorQLPreviewProvider)
final class PreviewProvider: QLPreviewProvider, QLPreviewingController {

    func providePreview(for request: QLFilePreviewRequest,
                        completionHandler handler: @escaping (QLPreviewReply?, Error?) -> Void) {
        providerLog.notice("providePreview: \(request.fileURL.lastPathComponent, privacy: .public)")
        do {
            let html = try QLMarkdownRenderer.renderHTML(forFileAt: request.fileURL)
            providerLog.notice("render ok, html bytes=\(html.utf8.count)")
            let reply = QLPreviewReply(
                dataOfContentType: .html,
                contentSize: CGSize(width: 720, height: 960)
            ) { _ in
                Data(html.utf8)
            }
            handler(reply, nil)
        } catch {
            providerLog.error("render failed: \(error.localizedDescription, privacy: .public)，退回纯文本")
            // 渲染失败不退空：系统直接显示等宽纯文本，QL 至少能看到源文件内容
            if let markdown = try? String(contentsOf: request.fileURL, encoding: .utf8) {
                let html = QLMarkdownRenderer.plainTextHTML(markdown)
                let reply = QLPreviewReply(
                    dataOfContentType: .html,
                    contentSize: CGSize(width: 720, height: 960)
                ) { _ in
                    Data(html.utf8)
                }
                handler(reply, nil)
            } else {
                handler(nil, error)
            }
        }
    }
}
