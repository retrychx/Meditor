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
    var rootURL: URL?

    /// Only these files are accessible via the share server.
    @ObservationIgnored
    var allowedFiles: [URL] = []

    func start(preferredPort: UInt16 = 8899) {
        guard !isRunning else { return }
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: preferredPort)!)
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
    }

    var shareURL: String {
        "http://\(localAddress):\(port)"
    }

    // MARK: - Connection handling

    private func handleConnection(_ connection: NWConnection) {
        connections.append(connection)
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, _ in
            Task { @MainActor in
                guard let self, let data else {
                    connection.cancel()
                    return
                }
                let request = String(data: data, encoding: .utf8) ?? ""
                self.respond(to: request, on: connection)
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
        let decodedPath = path.removingPercentEncoding ?? path

        // All document routes must start with /meditor/
        guard decodedPath.hasPrefix(Self.pathPrefix) else {
            send(build404Response(), on: connection)
            return
        }

        let relativePath = String(decodedPath.dropFirst(Self.pathPrefix.count))
        let cleaned = relativePath.replacingOccurrences(of: "..", with: "")
        let fileURL = rootURL.appendingPathComponent(cleaned)

        // Only serve files explicitly in the allowlist
        let isAllowed = allowedFiles.contains(where: { $0.path == fileURL.path })
        guard isAllowed else {
            // Allow static assets (images, css, js) referenced by allowed docs
            let ext = fileURL.pathExtension.lowercased()
            let isAsset = !["md", "html", "htm"].contains(ext) && !ext.isEmpty
            if isAsset, fileURL.path.hasPrefix(rootURL.path) {
                send(serveStaticFile(path: "/" + cleaned, rootURL: rootURL) ?? build404Response(), on: connection)
            } else {
                send(build404Response(), on: connection)
            }
            return
        }

        let responseData: Data
        if cleaned.hasSuffix(".md") {
            responseData = renderMarkdown(path: "/" + cleaned, rootURL: rootURL)
        } else {
            responseData = serveStaticFile(path: "/" + cleaned, rootURL: rootURL) ?? build404Response()
        }

        send(responseData, on: connection)
    }

    private func send(_ data: Data, on connection: NWConnection) {
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
        connections.removeAll { $0 === connection }
    }

    private func parseRequestPath(_ request: String) -> String {
        let lines = request.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else { return "/" }
        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2 else { return "/" }
        return parts[1]
    }

    /// Generate the share URL for a specific file.
    func shareURLForFile(_ fileURL: URL) -> String? {
        guard let rootURL, fileURL.path.hasPrefix(rootURL.path) else { return nil }
        let relative = fileURL.path.replacingOccurrences(of: rootURL.path + "/", with: "")
        let encoded = relative.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? relative
        return "\(shareURL)\(Self.pathPrefix)\(encoded)"
    }

    // MARK: - Markdown rendering

    private func renderMarkdown(path: String, rootURL: URL) -> Data {
        let cleaned = path.replacingOccurrences(of: "..", with: "")
        let fileURL = rootURL.appendingPathComponent(cleaned)
        guard fileURL.path.hasPrefix(rootURL.path),
              let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return build404Response()
        }

        let escapedContent = content
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")

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
        html, body { background: #1a1a2e; color: #e0e0e0; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'SF Pro', sans-serif;
            font-size: 15px; line-height: 1.7;
            max-width: 860px; margin: 0 auto;
            padding: 24px clamp(18px, 3vw, 36px);
        }
        .nav { margin-bottom: 20px; font-size: 13px; }
        .nav a { color: #7cb3ff; text-decoration: none; }
        .nav a:hover { text-decoration: underline; }
        h1,h2,h3,h4,h5,h6 { color: #fff; margin-top: 28px; margin-bottom: 12px; font-weight: 600; }
        h1 { font-size: 1.75em; border-bottom: 1px solid #333; padding-bottom: 10px; margin-top: 0; }
        h2 { font-size: 1.3em; border-bottom: 1px solid #333; padding-bottom: 6px; }
        p { margin-bottom: 16px; }
        a { color: #7cb3ff; }
        code { font-family: 'SF Mono', Menlo, monospace; font-size: 13px; padding: 2px 6px; border-radius: 4px; background: #2a2a3e; }
        pre { margin-bottom: 16px; border-radius: 8px; overflow: hidden; }
        pre code { background: none; padding: 16px; display: block; overflow-x: auto; border: 1px solid #333; border-radius: 8px; }
        blockquote { margin: 0 0 16px; padding: 0 16px; color: #aaa; border-left: 4px solid #444; }
        ul, ol { padding-left: 2em; margin-bottom: 16px; }
        li { margin-bottom: 4px; }
        table { border-collapse: collapse; width: 100%; margin-bottom: 16px; }
        th, td { border: 1px solid #333; padding: 8px 12px; text-align: left; }
        th { background: #2a2a3e; font-weight: 600; }
        img { max-width: 100%; border-radius: 6px; }
        hr { height: 1px; border: none; background: #333; margin: 28px 0; }
        .hljs { background: #1e1e2e; }
        </style>
        </head>
        <body>
        <div class="nav"><span>MEditor Share</span></div>
        <div id="content"></div>
        <script>\(markedJS)</script>
        <script>\(highlightJS)</script>
        <script>
        marked.setOptions({
            highlight: function(code, lang) {
                if (lang && hljs.getLanguage(lang)) {
                    return hljs.highlight(code, {language: lang}).value;
                }
                return hljs.highlightAuto(code).value;
            }
        });
        var md = `\(escapedContent)`;
        document.getElementById('content').innerHTML = marked.parse(md);
        </script>
        </body>
        </html>
        """
        return buildHTMLResponse(html)
    }

    private func loadBundledJS(_ filename: String) -> String {
        guard let root = PreviewResourceLocator.resourcesRoot() else { return "" }
        let url = root.appendingPathComponent(filename)
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    // MARK: - Static file serving

    private func serveStaticFile(path: String, rootURL: URL) -> Data? {
        let cleaned = path.replacingOccurrences(of: "..", with: "")
        let fileURL = rootURL.appendingPathComponent(cleaned)
        guard fileURL.path.hasPrefix(rootURL.path) else { return nil }
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
