import Foundation
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

/// 发布前把 HTML 里引用的本地图片内联成 data URI。
///
/// 预览导出的 `<img src>` 有五种形态：
///   - `meditor-asset://local/<编码后的绝对路径>`（macOS 预览对绝对路径的改写）
///   - `file:///…`（未走 render.js 改写的原始 file URL）
///   - 相对路径（`./pic.png`、`../assets/pic.png`——相对文档所在目录）
///   - `http(s)://…`（远程图，保持原样，线上直接可用）
///   - `data:…`（已是内联，跳过）
///
/// 单图 / 总量都有上限：超限的图保留原 src（页面结构完整，图线上不可见），
/// 保证整篇 HTML 仍低于 Worker 的 4MB 上限。
enum ShareImageInliner {

    /// 单张图片内联上限（1.5MB）。
    static let maxImageBytes = 1_500_000
    /// 全部图片内联总量上限（3MB，给正文与 CSS 留出 4MB 内的余量）。
    static let maxTotalInlineBytes = 3_000_000

    private static let imgSrcPattern: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"<img\b[^>]*?\bsrc="([^"]*)""#, options: .caseInsensitive)

    /// 把 html 中可内联的本地图片改写为 data URI，返回改写后的 HTML。
    /// - Parameter baseDirectory: 相对路径图片的解析基准（通常是文档所在目录）。
    static func inlineImages(in html: String, baseDirectory: URL) -> String {
        let nsHTML = html as NSString
        let matches = imgSrcPattern?.matches(in: html, range: NSRange(location: 0, length: nsHTML.length)) ?? []
        guard !matches.isEmpty else { return html }

        // 第一遍（正序）：决定每张图是否内联——预算从文档头部开始分配，
        // 靠前的图优先内联；超限的图保留原 src。
        var replacements: [String?] = []
        var inlinedTotal = 0
        for match in matches {
            guard let srcRange = Range(match.range(at: 1), in: html) else {
                replacements.append(nil)
                continue
            }
            let src = String(html[srcRange])
            guard let fileURL = resolveFileURL(src: src, baseDirectory: baseDirectory),
                  let data = loadImageData(at: fileURL, budget: maxImageBytes),
                  inlinedTotal + data.count <= maxTotalInlineBytes else {
                replacements.append(nil)
                continue
            }
            inlinedTotal += data.count
            let mime = mimeType(forPathExtension: fileURL.pathExtension)
            replacements.append("data:\(mime);base64,\(data.base64EncodedString())")
        }

        // 第二遍（逆序替换）：后面的替换不影响前面 match 的 range。
        var result = html
        for (index, match) in matches.enumerated().reversed() {
            guard let dataURI = replacements[index],
                  let srcRange = Range(match.range(at: 1), in: result) else { continue }
            result.replaceSubrange(srcRange, with: dataURI)
        }
        return result
    }

    // MARK: - src → 本地文件 URL（返回 nil = 不内联）

    private static func resolveFileURL(src: String, baseDirectory: URL) -> URL? {
        if src.isEmpty || src.hasPrefix("data:") || src.hasPrefix("http://") || src.hasPrefix("https://") {
            return nil
        }
        if src.hasPrefix("meditor-asset://") {
            guard let url = URL(string: src) else { return nil }
            let decoded = url.path.removingPercentEncoding ?? url.path
            return URL(fileURLWithPath: (decoded as NSString).standardizingPath)
        }
        if src.hasPrefix("file://") {
            guard let url = URL(string: src) else { return nil }
            return url
        }
        // 相对路径：先解百分号编码，再相对文档目录解析
        let decoded = src.removingPercentEncoding ?? src
        return baseDirectory.appendingPathComponent(decoded).standardizedFileURL
    }

    // MARK: - 读文件（带体积预算与类型检查）

    private static func loadImageData(at url: URL, budget: Int) -> Data? {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue,
              let attrs = try? fm.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int,
              size > 0, size <= budget else { return nil }
        return fm.contents(atPath: url.path)
    }

    private static func mimeType(forPathExtension ext: String) -> String {
        #if canImport(UniformTypeIdentifiers)
        if let type = UTType(filenameExtension: ext.lowercased()), let mime = type.preferredMIMEType {
            return mime
        }
        #endif
        return "application/octet-stream"
    }
}
