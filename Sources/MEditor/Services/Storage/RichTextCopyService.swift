import AppKit

/// 「复制为富文本」：把预览渲染出的 HTML 正文包装成粘贴友好的自包含 HTML，
/// 转成 NSAttributedString 后同时给剪贴板 RTF / HTML / 纯文本三个 flavor，
/// 贴到飞书/邮件/备忘录能保留标题、列表、表格、代码块样式。
enum RichTextCopyService {

    /// 粘贴友好样式：浅色、中性灰边框，不跟随预览主题（目标 App 大多白底）。
    /// 表格显式给 1px 边框——NSAttributedString 的 HTML 导入对 CSS 支持有限，
    /// 边框另由 applyTableBorders 在 NSTextTableBlock 层兜底。
    static let pasteboardCSS = """
    body { font-family: -apple-system, "PingFang SC", sans-serif; font-size: 14px; \
    color: #1f2328; line-height: 1.6; }
    h1 { font-size: 26px; border-bottom: 1px solid #d0d7de; padding-bottom: 6px; }
    h2 { font-size: 20px; border-bottom: 1px solid #eaecef; padding-bottom: 4px; }
    h3 { font-size: 16px; }
    h4, h5, h6 { font-size: 14px; }
    code { font-family: Menlo, monospace; font-size: 13px; \
    background-color: #eff1f3; padding: 2px 5px; border-radius: 4px; }
    pre { background-color: #f6f8fa; border: 1px solid #e5e7eb; \
    border-radius: 6px; padding: 12px; }
    pre code { background-color: transparent; padding: 0; }
    blockquote { margin-left: 0; padding-left: 14px; \
    border-left: 3px solid #d0d7de; color: #59636e; }
    table { border-collapse: collapse; }
    th, td { border: 1px solid #d0d7de; padding: 6px 12px; }
    th { background-color: #f6f8fa; }
    a { color: #0969da; }
    hr { border: none; border-top: 1px solid #d0d7de; }
    img { max-width: 100%; }
    """

    /// 把渲染好的正文 HTML 包成完整文档（纯字符串拼接，可测）。
    static func pasteboardHTML(bodyHTML: String, title: String) -> String {
        """
        <!DOCTYPE html>
        <html><head><meta charset="UTF-8">
        <title>\(escapeHTML(title))</title>
        <style>\(pasteboardCSS)</style>
        </head><body>\(bodyHTML)</body></html>
        """
    }

    static func escapeHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// HTML → 富文本，并补表格边框。解析失败返回 nil。
    /// 注意：AppKit 的 HTML 导入必须主线程调用。
    @MainActor
    static func makeAttributedString(fromPasteboardHTML html: String) -> NSMutableAttributedString? {
        guard let data = html.data(using: .utf8),
              let parsed = try? NSMutableAttributedString(
                html: data,
                options: [.characterEncoding: NSUTF8StringEncoding],
                documentAttributes: nil) else { return nil }
        applyTableBorders(to: parsed)
        return parsed
    }

    /// 给所有表格单元格强制加边框——HTML 导入常丢 CSS border，
    /// 直接写 NSTextTableBlock 层最可靠。
    static func applyTableBorders(to attr: NSMutableAttributedString) {
        let fullRange = NSRange(location: 0, length: attr.length)
        attr.enumerateAttribute(.paragraphStyle, in: fullRange) { value, _, _ in
            guard let style = value as? NSParagraphStyle else { return }
            for block in style.textBlocks {
                guard let tableBlock = block as? NSTextTableBlock else { continue }
                tableBlock.setWidth(0.5, type: .absoluteValueType, for: .border)
                tableBlock.setBorderColor(NSColor(white: 0.75, alpha: 1))
            }
        }
    }

    /// 把 <img> 的相对 src 按 baseURL（文档所在目录）解析成绝对 file:// URL。
    /// 纯字符串处理，可测。已有 scheme（http:/data:/file: 等）或协议相对（//）的 src 不动。
    static func absolutizingImageSources(in bodyHTML: String, baseURL: URL) -> String {
        let pattern = try? NSRegularExpression(
            pattern: #"<img\b[^>]*?\bsrc="([^"]*)""#, options: .caseInsensitive)
        guard let pattern else { return bodyHTML }
        var result = bodyHTML
        let matches = pattern.matches(
            in: bodyHTML, range: NSRange(bodyHTML.startIndex..., in: bodyHTML))
        // 从后往前替换，保持前面 match 的偏移有效
        for match in matches.reversed() {
            guard let srcRange = Range(match.range(at: 1), in: result) else { continue }
            let src = String(result[srcRange])
            guard let resolved = resolveImageSource(src, baseURL: baseURL) else { continue }
            result.replaceSubrange(srcRange, with: resolved)
        }
        return result
    }

    /// 相对 src → 绝对 URL 字符串；已是绝对 URL 时返回 nil（不替换）。
    static func resolveImageSource(_ src: String, baseURL: URL) -> String? {
        if src.hasPrefix("//") { return nil }
        if src.range(of: #"^[a-zA-Z][a-zA-Z0-9+.\-]*:"#, options: .regularExpression) != nil {
            return nil
        }
        if let url = URL(string: src, relativeTo: baseURL) {
            return url.absoluteURL.absoluteString
        }
        // 含空格等非法 URL 字符的裸路径：按文件路径解析（自动百分号编码）
        return URL(fileURLWithPath: src, relativeTo: baseURL).standardized.absoluteString
    }

    /// 组装并写入剪贴板（RTF + HTML + 纯文本）。成功返回 true。
    /// - Parameter imageBaseURL: 文档所在目录。<img> 的相对 src 会按它解析成
    ///   绝对 file:// URL——直接复制相对路径到目标 App 没有相对基准，会破图。
    @MainActor
    @discardableResult
    static func copyRichText(bodyHTML: String, title: String, plainText: String,
                             imageBaseURL: URL? = nil) -> Bool {
        let resolvedBody = imageBaseURL.map { absolutizingImageSources(in: bodyHTML, baseURL: $0) } ?? bodyHTML
        let html = pasteboardHTML(bodyHTML: resolvedBody, title: title)
        guard let attr = makeAttributedString(fromPasteboardHTML: html),
              let rtf = try? attr.data(
                from: NSRange(location: 0, length: attr.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
              ) else { return false }

        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(rtf, forType: .rtf)
        pb.setString(html, forType: .html)
        pb.setString(plainText.isEmpty ? attr.string : plainText, forType: .string)
        return true
    }
}
