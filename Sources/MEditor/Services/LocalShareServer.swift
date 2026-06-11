import Foundation
import Network
import Observation

/// A minimal HTTP server using NWListener that serves project documents
/// over the local network. Colleagues access via browser at http://<IP>:<port>.
///
/// Routes:
/// - `/` → file directory listing (.md and .html files)
/// - `/path/to/file.md` → rendered Markdown (using marked.js + highlight.js)
/// - `/path/to/file.html` → served directly
/// - other paths → static file serving
@MainActor
@Observable
final class LocalShareServer {
    private(set) var isRunning = false
    private(set) var port: UInt16 = 0
    private(set) var localAddress: String = ""

    @ObservationIgnored
    private var listener: NWListener?
    @ObservationIgnored
    private var connections: [NWConnection] = []

    /// The root URL of the project.
    @ObservationIgnored
    var rootURL: URL? {
        didSet { refreshAllowLists() }
    }

    /// Only these files are accessible via the share server.
    @ObservationIgnored
    var allowedFiles: [URL] = [] {
        didSet { refreshAllowLists() }
    }

    @ObservationIgnored
    private var allowedDocumentPaths: Set<String> = []
    @ObservationIgnored
    private var allowedAssetPaths: Set<String> = []

    /// One-time access token, regenerated on every `start()`. Required as the
    /// first path segment (`/meditor/<token>/...`) so only holders of the
    /// freshly-shared URL can read documents over the LAN.
    @ObservationIgnored
    private(set) var accessToken: String = ""

    private static let maxRequestHeaderBytes = 64 * 1024

    func start(preferredPort: UInt16 = 8899) {
        guard !isRunning else { return }
        guard let nwPort = NWEndpoint.Port(rawValue: preferredPort) else { return }
        accessToken = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            listener = try NWListener(using: params, on: nwPort)
        } catch {
            return
        }

        listener?.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .ready:
                    if let port = self.listener?.port?.rawValue {
                        self.port = port
                    }
                    self.localAddress = Self.getLocalIP() ?? "localhost"
                    self.isRunning = true
                case .failed, .cancelled:
                    self.isRunning = false
                default:
                    break
                }
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                self?.handleConnection(connection)
            }
        }

        listener?.start(queue: .main)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        connections.forEach { $0.cancel() }
        connections.removeAll()
        isRunning = false
        port = 0
        accessToken = ""
    }

    var shareURL: String {
        "http://\(localAddress):\(port)"
    }

    // MARK: - Connection handling

    private func handleConnection(_ connection: NWConnection) {
        connections.append(connection)
        connection.start(queue: .main)
        receiveRequest(on: connection, accumulated: Data())
    }

    private func receiveRequest(on connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self else {
                    connection.cancel()
                    return
                }

                if error != nil {
                    self.close(connection)
                    return
                }

                var buffer = accumulated
                if let data {
                    buffer.append(data)
                }

                if let request = self.completeRequest(from: buffer) {
                    self.respond(to: request, on: connection)
                    return
                }

                if isComplete || buffer.count > Self.maxRequestHeaderBytes {
                    self.send(self.build404Response(), on: connection)
                    return
                }

                self.receiveRequest(on: connection, accumulated: buffer)
            }
        }
    }

    private static let pathPrefix = "/meditor/"

    private func respond(to request: String, on connection: NWConnection) {
        guard let rootURL else {
            send(build404Response(), on: connection)
            return
        }

        let path = parseRequestPath(request)
        // Drop any query string before decoding / route matching.
        let pathOnly = path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? path
        let decodedPath = pathOnly.removingPercentEncoding ?? pathOnly

        // All document routes must start with /meditor/<token>/
        guard decodedPath.hasPrefix(Self.pathPrefix) else {
            send(build404Response(), on: connection)
            return
        }

        // First path segment after the prefix is the one-time access token.
        let afterPrefix = String(decodedPath.dropFirst(Self.pathPrefix.count))
        let segments = afterPrefix.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        guard let token = segments.first.map(String.init),
              !accessToken.isEmpty, token == accessToken else {
            send(build404Response(), on: connection)
            return
        }
        let relativePath = segments.count > 1 ? String(segments[1]) : ""

        // Resolve + confine to the project root (defeats ../ traversal).
        guard let fileURL = resolvedFileURL(relativePath, rootURL: rootURL) else {
            send(build404Response(), on: connection)
            return
        }

        // Only serve files explicitly in the allowlist
        let isAllowed = isAllowedDocument(fileURL)
        guard isAllowed else {
            if isAllowedAsset(fileURL) {
                send(serveStaticFile(fileURL: fileURL) ?? build404Response(), on: connection)
            } else {
                send(build404Response(), on: connection)
            }
            return
        }

        let responseData: Data
        if fileURL.pathExtension.lowercased() == "md" {
            responseData = renderMarkdown(fileURL: fileURL)
        } else {
            responseData = serveStaticFile(fileURL: fileURL) ?? build404Response()
        }

        send(responseData, on: connection)
    }

    /// Resolve a relative request path against the project root and verify the
    /// result stays inside it. Returns nil for anything that escapes (e.g. `../`).
    private func resolvedFileURL(_ relativePath: String, rootURL: URL) -> URL? {
        let fileURL = rootURL.appendingPathComponent(relativePath).standardizedFileURL
        let root = rootURL.standardizedFileURL
        guard fileURL.path == root.path || fileURL.path.hasPrefix(root.path + "/") else { return nil }
        return fileURL
    }

    private func send(_ data: Data, on connection: NWConnection) {
        connection.send(content: data, completion: .contentProcessed { _ in
            Task { @MainActor in
                self.close(connection)
            }
        })
    }

    private func close(_ connection: NWConnection) {
        connection.cancel()
        connections.removeAll { $0 === connection }
    }

    private func completeRequest(from data: Data) -> String? {
        guard let range = Self.headerTerminatorRange(in: data) else { return nil }
        return String(data: Data(data[..<range.lowerBound]), encoding: .utf8)
    }

    private func parseRequestPath(_ request: String) -> String {
        let lines = request.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else { return "/" }
        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2 else { return "/" }
        return parts[1]
    }

    static func headerTerminatorRange(in data: Data) -> Range<Data.Index>? {
        data.range(of: Data([0x0D, 0x0A, 0x0D, 0x0A]))
    }

    /// Generate the share URL for a specific file.
    func shareURLForFile(_ fileURL: URL) -> String? {
        guard let rootURL, !accessToken.isEmpty,
              isSameOrDescendant(fileURL, of: rootURL) else { return nil }
        let rootPath = rootURL.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        let relative = filePath == rootPath
            ? ""
            : String(filePath.dropFirst(rootPath.count + 1))
        let encoded = relative.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? relative
        return "\(shareURL)\(Self.pathPrefix)\(accessToken)/\(encoded)"
    }

    // MARK: - Markdown rendering

    private func renderMarkdown(fileURL: URL) -> Data {
        guard let content = try? TextFileDecoder.decode(contentsOf: fileURL) else {
            return build404Response()
        }
        guard let encodedMarkdown = Self.inlineJavaScriptStringLiteral(content) else {
            return build404Response()
        }

        let title = fileURL.deletingPathExtension().lastPathComponent

        // Load marked.js and highlight.js from bundle resources
        let markedJS = loadBundledJS("marked.min.js")
        let highlightJS = loadBundledJS("highlight.min.js")

        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>\(title) · MEditor Share</title>
        <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        html, body { background: #ffffff; color: #1d1d1f; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'SF Pro', sans-serif;
            font-size: 15px; line-height: 1.7;
            max-width: 860px; margin: 0 auto;
            padding: 24px clamp(18px, 3vw, 36px);
        }
        .nav { margin-bottom: 20px; font-size: 13px; }
        .nav a { color: #3b82f6; text-decoration: none; }
        .nav a:hover { text-decoration: underline; }
        h1,h2,h3,h4,h5,h6 { color: #1d1d1f; margin-top: 28px; margin-bottom: 12px; font-weight: 600; }
        h1 { font-size: 1.75em; border-bottom: 1px solid #e5e5e5; padding-bottom: 10px; margin-top: 0; }
        h2 { font-size: 1.3em; border-bottom: 1px solid #e5e5e5; padding-bottom: 6px; }
        p { margin-bottom: 16px; }
        a { color: #3b82f6; }
        code { font-family: 'SF Mono', Menlo, monospace; font-size: 13px; padding: 2px 6px; border-radius: 4px; background: #f3f4f6; }
        pre { margin-bottom: 16px; border-radius: 8px; overflow: hidden; }
        pre code { background: none; padding: 16px; display: block; overflow-x: auto; border: 1px solid #e5e5e5; border-radius: 8px; background: #f9fafb; }
        blockquote { margin: 0 0 16px; padding: 0 16px; color: #6b7280; border-left: 4px solid #d1d5db; }
        ul, ol { padding-left: 2em; margin-bottom: 16px; }
        li { margin-bottom: 4px; }
        table { border-collapse: collapse; width: 100%; margin-bottom: 16px; }
        th, td { border: 1px solid #e5e5e5; padding: 8px 12px; text-align: left; }
        th { background: #f3f4f6; font-weight: 600; }
        img { max-width: 100%; border-radius: 6px; }
        hr { height: 1px; border: none; background: #e5e5e5; margin: 28px 0; }
        .hljs { background: #1e1e2e; }
        </style>
        </head>
        <body>
        <div class="nav"><span>MEditor Share</span></div>
        <div id="content"></div>
        <script>\(markedJS)</script>
        <script>\(highlightJS)</script>
        <script>
        function escapeHtml(text) {
            return text
                .replace(/&/g, '&amp;')
                .replace(/</g, '&lt;')
                .replace(/>/g, '&gt;')
                .replace(/"/g, '&quot;')
                .replace(/'/g, '&#39;');
        }
        marked.setOptions({
            highlight: function(code, lang) {
                if (lang && hljs.getLanguage(lang)) {
                    return hljs.highlight(code, {language: lang}).value;
                }
                return escapeHtml(code);
            }
        });
        var md = \(encodedMarkdown);
        document.getElementById('content').innerHTML = marked.parse(md);
        </script>
        </body>
        </html>
        """
        return buildHTMLResponse(html)
    }

    private func refreshAllowLists() {
        allowedDocumentPaths.removeAll()
        allowedAssetPaths.removeAll()

        guard let rootURL else { return }
        for fileURL in allowedFiles {
            guard isSameOrDescendant(fileURL, of: rootURL) else { continue }
            let standardized = fileURL.standardizedFileURL
            allowedDocumentPaths.insert(standardized.path)
            allowedAssetPaths.formUnion(referencedAssetPaths(in: standardized, rootURL: rootURL))
        }
    }

    func isAllowedDocument(_ fileURL: URL) -> Bool {
        allowedDocumentPaths.contains(fileURL.standardizedFileURL.path)
    }

    func isAllowedAsset(_ fileURL: URL) -> Bool {
        allowedAssetPaths.contains(fileURL.standardizedFileURL.path)
    }

    private func referencedAssetPaths(in fileURL: URL, rootURL: URL) -> Set<String> {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return []
        }

        let candidates: [String]
        switch fileURL.pathExtension.lowercased() {
        case "html", "htm":
            candidates = Self.extractHTMLReferences(from: content)
        case "md":
            candidates = Self.extractMarkdownReferences(from: content) + Self.extractHTMLReferences(from: content)
        default:
            candidates = []
        }

        return Set(candidates.compactMap { raw in
            guard let resolved = resolveAssetReference(raw, relativeTo: fileURL, rootURL: rootURL) else {
                return nil
            }
            return resolved.path
        })
    }

    private func resolveAssetReference(_ rawReference: String, relativeTo fileURL: URL, rootURL: URL) -> URL? {
        var reference = rawReference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reference.isEmpty else { return nil }

        if reference.hasPrefix("<"), reference.hasSuffix(">") {
            reference.removeFirst()
            reference.removeLast()
        }
        if let whitespace = reference.firstIndex(where: \.isWhitespace) {
            reference = String(reference[..<whitespace])
        }

        let lowered = reference.lowercased()
        guard !lowered.hasPrefix("#"),
              !lowered.hasPrefix("data:"),
              !lowered.hasPrefix("mailto:"),
              !lowered.hasPrefix("javascript:"),
              !lowered.hasPrefix("tel:"),
              URL(string: reference)?.scheme == nil else {
            return nil
        }

        let resolved = fileURL.deletingLastPathComponent()
            .appendingPathComponent(reference)
            .standardizedFileURL
        guard isSameOrDescendant(resolved, of: rootURL) else { return nil }

        let ext = resolved.pathExtension.lowercased()
        guard !ext.isEmpty, !["md", "html", "htm"].contains(ext) else { return nil }
        return resolved
    }

    private func isSameOrDescendant(_ url: URL, of rootURL: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let rootPath = rootURL.standardizedFileURL.path
        return path == rootPath || path.hasPrefix(rootPath + "/")
    }

    static func inlineJavaScriptStringLiteral(_ string: String) -> String? {
        guard let data = try? JSONEncoder().encode(string),
              var encoded = String(data: data, encoding: .utf8) else {
            return nil
        }
        encoded = encoded.replacingOccurrences(of: "</", with: "<\\/")
        return encoded
    }

    static func extractHTMLReferences(from content: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?:src|href)\s*=\s*["']([^"']+)["']"#,
            options: [.caseInsensitive]
        ) else {
            return []
        }

        let range = NSRange(content.startIndex..., in: content)
        return regex.matches(in: content, range: range).compactMap { match in
            guard let capture = Range(match.range(at: 1), in: content) else { return nil }
            return String(content[capture])
        }
    }

    static func extractMarkdownReferences(from content: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"!?\[[^\]]*]\(([^)]+)\)"#
        ) else {
            return []
        }

        let range = NSRange(content.startIndex..., in: content)
        return regex.matches(in: content, range: range).compactMap { match in
            guard let capture = Range(match.range(at: 1), in: content) else { return nil }
            return String(content[capture])
        }
    }

    private func loadBundledJS(_ filename: String) -> String {
        guard let root = PreviewResourceLocator.resourcesRoot() else { return "" }
        let url = root.appendingPathComponent(filename)
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    // MARK: - Static file serving

    private func serveStaticFile(fileURL: URL) -> Data? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }

        let mime = mimeType(for: fileURL.pathExtension)
        let header = "HTTP/1.1 200 OK\r\nContent-Type: \(mime)\r\nContent-Length: \(data.count)\r\nAccess-Control-Allow-Origin: *\r\n\r\n"
        var response = Data(header.utf8)
        response.append(data)
        return response
    }

    // MARK: - Response builders

    private func buildHTMLResponse(_ html: String) -> Data {
        let body = Data(html.utf8)
        let header = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\nAccess-Control-Allow-Origin: *\r\n\r\n"
        var response = Data(header.utf8)
        response.append(body)
        return response
    }

    private func build404Response() -> Data {
        let body = "<html><body><h1>404 Not Found</h1></body></html>"
        let bodyData = Data(body.utf8)
        let header = "HTTP/1.1 404 Not Found\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(bodyData.count)\r\n\r\n"
        var response = Data(header.utf8)
        response.append(bodyData)
        return response
    }

    private func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "html", "htm": return "text/html; charset=utf-8"
        case "css": return "text/css"
        case "js": return "application/javascript"
        case "json": return "application/json"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "svg": return "image/svg+xml"
        case "woff", "woff2": return "font/woff2"
        case "ttf": return "font/ttf"
        case "pdf": return "application/pdf"
        default: return "application/octet-stream"
        }
    }

    // MARK: - Network utility

    private static func getLocalIP() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            guard addrFamily == UInt8(AF_INET) else { continue }

            let name = String(cString: interface.ifa_name)
            guard name == "en0" || name == "en1" else { continue }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                       &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
            address = String(cString: hostname)
            break
        }
        return address
    }
}
