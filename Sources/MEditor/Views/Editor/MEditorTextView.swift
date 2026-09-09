import AppKit

/// 编辑器专用 NSTextView：拦截 ⌘V 粘贴。处理顺序：粘贴板含图片（截图 /
/// Finder 复制的图片文件）时先走 ImageAssetService 落盘并插入 Markdown 引用；
/// 含 HTML（网页 / 飞书 / 公众号文章等富文本来源）时转 Markdown 插入；
/// 两者都不命中（handler 返回 false）时回退系统默认粘贴行为。
final class MEditorTextView: NSTextView {

    /// 返回 true = 已消费本次粘贴（图片已落盘并插入引用），不再走默认粘贴。
    var imagePasteHandler: ((NSPasteboard) -> Bool)?

    /// 返回 true = 已消费本次粘贴。注意该 handler 内部是异步的（离屏 WebView
    /// 做 HTML→Markdown 转换），返回 true 时插入可能尚未发生。
    var richPasteHandler: ((NSPasteboard) -> Bool)?

    override func paste(_ sender: Any?) {
        if let handler = imagePasteHandler, handler(.general) { return }
        if let handler = richPasteHandler, handler(.general) { return }
        super.paste(sender)
    }
}
