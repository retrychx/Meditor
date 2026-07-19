import UIKit
import WebKit

/// 共享 Mermaid 渲染引擎：单个离线 WKWebView 常驻，mermaid.min.js（约 3MB）只加载解析一次。
/// 渲染请求串行排队（mermaid.render 非线程安全，且共用同一个 JS 上下文），
/// 结果 PNG 按「缩放 + 代码串」做内存缓存——滚动复用、重开文档均即时出图。
@MainActor
final class MermaidRenderer: NSObject {
    static let shared = MermaidRenderer()

    struct Rendered {
        let image: UIImage
        /// SVG viewBox 的逻辑尺寸（pt），供布局参考。
        let size: CGSize
    }

    enum RenderError: LocalizedError {
        case engineUnavailable
        case jsFailed(String)
        case badImage

        var errorDescription: String? {
            switch self {
            case .engineUnavailable: return "图表引擎加载失败"
            case .jsFailed(let message): return message
            case .badImage: return "图表解码失败"
            }
        }
    }

    // MARK: - 缓存

    private final class RenderedBox {
        let value: Rendered
        init(_ value: Rendered) { self.value = value }
    }

    private let cache = NSCache<NSString, RenderedBox>()

    // MARK: - 引擎状态

    private var webView: WKWebView?
    private var ready: Result<Void, Error>?
    private var readyWaiters: [CheckedContinuation<Result<Void, Error>, Never>] = []

    // MARK: - 串行队列（baton-pass 信号量）

    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    private override init() {
        super.init()
        cache.countLimit = 60
    }

    /// 提前拉起引擎——JS 解析是冷启动大头，藏在用户阅读前文的时间里。
    func prewarm() {
        ensureEngine()
    }

    /// 预渲染一批图表：引擎预热后按文档顺序在后台填满缓存。
    /// 视图出现前的预热调用；块真正展示时 render() 命中缓存即时返回，
    /// 屏外的图表也不再等滚动到才开始渲染。失败忽略（视图会自行展示错误）。
    func preload(codes: [String], scale: CGFloat) {
        let pending = codes.filter { cache.object(forKey: "\(scale)|\($0)" as NSString) == nil }
        guard !pending.isEmpty else { return }
        prewarm()
        Task {
            for code in pending {
                _ = try? await render(code: code, scale: scale)
            }
        }
    }

    func render(code: String, scale: CGFloat) async throws -> Rendered {
        let key = "\(scale)|\(code)" as NSString
        if let hit = cache.object(forKey: key) { return hit.value }

        await acquire()
        defer { release() }

        // 排队期间可能有相同代码先渲染完，再查一次。
        if let hit = cache.object(forKey: key) { return hit.value }

        try await ensureReady()
        guard let webView else { throw RenderError.engineUnavailable }

        let raw: Any? = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Any?, Error>) in
            webView.callAsyncJavaScript(
                "return await renderMermaidPNG(code, scale);",
                arguments: ["code": code, "scale": scale],
                in: nil, in: .page
            ) { result in
                cont.resume(with: result.map { $0 as Any? })
            }
        }

        guard let dict = raw as? [String: Any] else { throw RenderError.badImage }
        if let error = dict["error"] as? String { throw RenderError.jsFailed(error) }
        guard let dataURL = dict["png"] as? String,
              let comma = dataURL.firstIndex(of: ","),
              let data = Data(base64Encoded: String(dataURL[dataURL.index(after: comma)...])),
              let image = UIImage(data: data, scale: scale),
              let width = (dict["width"] as? NSNumber)?.doubleValue,
              let height = (dict["height"] as? NSNumber)?.doubleValue,
              width > 0, height > 0 else { throw RenderError.badImage }

        let rendered = Rendered(image: image, size: CGSize(width: width, height: height))
        cache.setObject(RenderedBox(rendered), forKey: key)
        return rendered
    }

    // MARK: - 引擎生命周期

    private func ensureEngine() {
        guard webView == nil else { return }
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1024, height: 1024))
        webView.isOpaque = false
        webView.navigationDelegate = self
        self.webView = webView
        webView.loadHTMLString(Self.shell, baseURL: Bundle.main.resourceURL)
    }

    private func ensureReady() async throws {
        ensureEngine()
        if let ready { return try ready.get() }
        let result = await withCheckedContinuation { (cont: CheckedContinuation<Result<Void, Error>, Never>) in
            readyWaiters.append(cont)
        }
        try result.get()
    }

    private func finishReady(_ result: Result<Void, Error>) {
        guard ready == nil else { return }
        ready = result
        let pending = readyWaiters
        readyWaiters.removeAll()
        pending.forEach { $0.resume(returning: result) }
    }

    // MARK: - 串行队列原语

    private func acquire() async {
        if busy {
            await withCheckedContinuation { waiters.append($0) }
        } else {
            busy = true
        }
    }

    private func release() {
        if let next = waiters.first {
            waiters.removeFirst()
            next.resume()   // busy 保持 true，令牌直接移交
        } else {
            busy = false
        }
    }

    // MARK: - HTML 壳（与桌面端共用同一份 mermaid.min.js，渲染结果两端一致）

    private static let shell = """
    <!DOCTYPE html>
    <html><head>
    <meta charset="utf-8">
    <script src="mermaid.min.js"></script>
    <script>
    mermaid.initialize({
      startOnLoad: false,
      securityLevel: 'loose',
      theme: 'base',
      themeVariables: {
        background: '#FCFBF7',
        primaryColor: '#F4F2EC',
        primaryTextColor: '#201D17',
        primaryBorderColor: '#B8501F',
        lineColor: '#6F6A5C',
        secondaryColor: '#ECE8DC',
        tertiaryColor: '#ECE8DC',
        fontFamily: '-apple-system, sans-serif'
      }
    });
    var renderSeq = 0;
    async function renderMermaidPNG(code, scale) {
      try {
        const { svg } = await mermaid.render('mmd-' + (renderSeq++), code);
        const host = document.getElementById('host');
        host.innerHTML = svg;
        const el = host.querySelector('svg');
        let w = 0, h = 0;
        const vb = el.getAttribute('viewBox');
        if (vb) {
          const p = vb.split(/[ ,]+/).map(Number);
          if (p.length === 4 && p[2] > 0 && p[3] > 0) { w = p[2]; h = p[3]; }
        }
        if (!w || !h) {
          w = parseFloat(el.getAttribute('width')) || 0;
          h = parseFloat(el.getAttribute('height')) || 0;
        }
        if (!w || !h) {
          const r = el.getBoundingClientRect();
          w = r.width; h = r.height;
        }
        if (!w || !h) return { error: '无法测量图表尺寸' };
        el.setAttribute('width', String(w));
        el.setAttribute('height', String(h));
        const xml = new XMLSerializer().serializeToString(el);
        const img = new Image();
        await new Promise(function (resolve, reject) {
          img.onload = resolve;
          img.onerror = function () { reject(new Error('SVG 栅格化失败')); };
          img.src = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(xml);
        });
        const canvas = document.createElement('canvas');
        canvas.width = Math.round(w * scale);
        canvas.height = Math.round(h * scale);
        const ctx = canvas.getContext('2d');
        ctx.fillStyle = '#FCFBF7';
        ctx.fillRect(0, 0, canvas.width, canvas.height);
        ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
        return { png: canvas.toDataURL('image/png'), width: w, height: h };
      } catch (e) {
        return { error: String(e && e.message ? e.message : e) };
      }
    }
    </script>
    </head><body style="margin:0"><div id="host"></div></body></html>
    """
}

// MARK: - WKNavigationDelegate

extension MermaidRenderer: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        MainActor.assumeIsolated {
            finishReady(.success(()))
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        MainActor.assumeIsolated {
            finishReady(.failure(error))
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        MainActor.assumeIsolated {
            finishReady(.failure(error))
        }
    }
}
