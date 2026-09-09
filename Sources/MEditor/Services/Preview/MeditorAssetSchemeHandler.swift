import WebKit
import UniformTypeIdentifiers

/// Custom `WKURLSchemeHandler` that serves arbitrary local files from disk,
/// bypassing the single-directory restriction of `WKWebView.loadFileURL(_:allowingReadAccessTo:)`.
///
/// Why this exists: the Markdown preview loads `preview.html` from the app's
/// cache directory (`~/Library/Caches/com.meditor.preview/`) via `loadFileURL`,
/// which only grants read access to that one directory tree. Markdown source
/// files live elsewhere (the user's document folder), so relative image/asset
/// paths in the rendered HTML — resolved via `<base href>` — point outside the
/// sandboxed read-access boundary and WebKit silently refuses to load them.
/// This is a WebKit `loadFileURL` restriction, not App Sandbox — it applies
/// even when the app itself is unsandboxed.
///
/// `meditor-asset://<host>/<url-encoded-absolute-path>` sidesteps this
/// entirely: requests for this scheme never go through WebKit's file-access
/// check, so Swift can read any absolute path the user has filesystem
/// permission for.
final class MeditorAssetSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "meditor-asset"

    /// Build a `meditor-asset://` URL that resolves to `path` when used as a
    /// relative reference against a `<base href>` set to the directory
    /// returned by `baseURLString(forDirectory:)`.
    static func baseURLString(forDirectory directory: URL) -> String {
        var path = directory.standardizedFileURL.path
        if !path.hasSuffix("/") { path += "/" }
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        return "\(scheme)://local/\(encoded)"
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let requestURL = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }
        guard let filePath = Self.decodeFilePath(from: requestURL) else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }
        // 纵深防御：挡住明显敏感的目录前缀。主防线是渲染输出的 DOMPurify
        // 消毒 + CSP（connect-src 'none'），这里是就算攻击者最终构造出了
        // meditor-asset:// 请求，也不给读私钥/凭据/系统配置。
        guard !Self.isSensitivePath(filePath) else {
            urlSchemeTask.didFailWithError(URLError(.noPermissionsToReadFile))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: filePath, isDirectory: &isDirectory), !isDirectory.boolValue,
                  let data = fm.contents(atPath: filePath) else {
                DispatchQueue.main.async {
                    urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
                }
                return
            }

            let mimeType = Self.mimeType(forPathExtension: (filePath as NSString).pathExtension)
            let response = URLResponse(
                url: requestURL,
                mimeType: mimeType,
                expectedContentLength: data.count,
                textEncodingName: nil
            )

            DispatchQueue.main.async {
                urlSchemeTask.didReceive(response)
                urlSchemeTask.didReceive(data)
                urlSchemeTask.didFinish()
            }
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // Best-effort: reads complete synchronously on a background queue
        // above and there is no cancellable handle to interrupt.
    }

    /// Extract the absolute filesystem path encoded in a `meditor-asset://` URL,
    /// resolving any `../` segments introduced by relative markdown links.
    private static func decodeFilePath(from url: URL) -> String? {
        let encodedPath = url.path
        guard let decoded = encodedPath.removingPercentEncoding else { return nil }
        return (decoded as NSString).standardizingPath
    }

    /// 敏感路径前缀拦截（拆成纯函数便于单测）。
    /// 只挡"明确不该出现在预览里的"目录：私钥/凭据/系统配置。
    /// 注意 /etc 是 /private/etc 的符号链接，standardizingPath 不解符号链接，两个都要列。
    static func isSensitivePath(_ path: String, homeDirectory: String = NSHomeDirectory()) -> Bool {
        let prefixes = [
            homeDirectory + "/.ssh",
            homeDirectory + "/.aws",
            homeDirectory + "/.gnupg",
            homeDirectory + "/.kube",
            homeDirectory + "/.docker",
            homeDirectory + "/Library/Keychains",
            "/etc",
            "/private/etc",
        ]
        return prefixes.contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    private static func mimeType(forPathExtension ext: String) -> String {
        if let type = UTType(filenameExtension: ext.lowercased()), let mime = type.preferredMIMEType {
            return mime
        }
        return "application/octet-stream"
    }
}
