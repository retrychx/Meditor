import AppKit

/// 编辑器专用 NSTextView：拦截 ⌘V 粘贴，粘贴板含图片（截图 / Finder 复制的
/// 图片文件）时先走 ImageAssetService 落盘并插入 Markdown 引用；handler 返回
/// false（无图片或落盘失败）时回退系统默认粘贴行为。
final class MEditorTextView: NSTextView {

    /// 返回 true = 已消费本次粘贴（图片已落盘并插入引用），不再走默认粘贴。
    var imagePasteHandler: ((NSPasteboard) -> Bool)?

    override func paste(_ sender: Any?) {
        if let handler = imagePasteHandler, handler(.general) { return }
        super.paste(sender)
    }
}
