import SwiftUI
import WebKit

/// Renders Markdown content in a WKWebView using marked.js + highlight.js + mermaid.js.
/// All JS/CSS resources are bundled locally — zero network/CDN dependency.
struct MarkdownWebPreview: View {
    let content: String
    var scrollPercentage: Double = 0
    var onScrollChange: ((Double) -> Void)? = nil

    var body: some View {
        MarkdownWebView(
            content: content,
            scrollPercentage: scrollPercentage,
            onScrollChange: onScrollChange
        )
    }
}

// MARK: - WKWebView

private struct MarkdownWebView: NSViewRepresentable {
    let content: String
    var scrollPercentage: Double
    var onScrollChange: ((Double) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onScrollChange: onScrollChange)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "scrollHandler")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.prepareResources()
        context.coordinator.lastLoadedContent = content
        loadHTML(into: webView, content: content, coordinator: context.coordinator)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Reload HTML if content changed
        if content != context.coordinator.lastLoadedContent {
            context.coordinator.lastLoadedContent = content
            loadHTML(into: webView, content: content, coordinator: context.coordinator)
            return
        }

        // Sync scroll position from editor (unless triggered by preview itself)
        guard !context.coordinator.isProgrammaticScroll else {
            context.coordinator.isProgrammaticScroll = false
            return
        }

        let js = "window.scrollTo(0, (document.documentElement.scrollHeight - window.innerHeight) * \(scrollPercentage));"
        context.coordinator.isProgrammaticScroll = true
        webView.evaluateJavaScript(js)
    }

    private func loadHTML(into webView: WKWebView, content: String, coordinator: Coordinator) {
        guard let html = try? htmlContent(content: content) else { return }

        let fileURL = coordinator.previewDir.appendingPathComponent("preview.html")
        try? html.write(to: fileURL, atomically: true, encoding: .utf8)
        webView.loadFileURL(fileURL, allowingReadAccessTo: coordinator.previewDir)
    }

    // MARK: - HTML Generation

    private func htmlContent(content: String) throws -> String {
        let encoder = JSONEncoder()
        guard let contentData = try? encoder.encode(content),
              let contentJSON = String(data: contentData, encoding: .utf8) else {
            throw NSError(domain: "MarkdownWebPreview", code: 1, userInfo: nil)
        }

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <script src="marked.min.js"></script>
        <script src="highlight.min.js"></script>
        <script src="mermaid.min.js"></script>
        <style>
          /* highlight.js GitHub theme — light */
          .hljs{color:#24292e;background:#f6f8fa}
          .hljs-doctag,.hljs-keyword,.hljs-meta .hljs-keyword,.hljs-template-tag,.hljs-template-variable,.hljs-type,.hljs-variable.language_{color:#d73a49}
          .hljs-title,.hljs-title.class_,.hljs-title.class_.inherited__,.hljs-title.function_{color:#6f42c1}
          .hljs-attr,.hljs-attribute,.hljs-literal,.hljs-meta,.hljs-number,.hljs-operator,.hljs-selector-attr,.hljs-selector-class,.hljs-selector-id,.hljs-variable{color:#005cc5}
          .hljs-meta .hljs-string,.hljs-regexp,.hljs-string{color:#032f62}
          .hljs-built_in,.hljs-symbol{color:#e36209}
          .hljs-code,.hljs-comment,.hljs-formula{color:#6a737d}
          .hljs-name,.hljs-quote,.hljs-selector-pseudo,.hljs-selector-tag{color:#22863a}
          .hljs-subst{color:#24292e}
          .hljs-section{color:#005cc5;font-weight:700}
          .hljs-bullet{color:#735c0f}
          .hljs-emphasis{color:#24292e;font-style:italic}
          .hljs-strong{color:#24292e;font-weight:700}
          .hljs-addition{color:#22863a;background:#f0fff4}
          .hljs-deletion{color:#b31d28;background:#ffeef0}

          @media (prefers-color-scheme: dark) {
          .hljs{color:#c9d1d9;background:#161b22}
          .hljs-doctag,.hljs-keyword,.hljs-meta .hljs-keyword,.hljs-template-tag,.hljs-template-variable,.hljs-type,.hljs-variable.language_{color:#ff7b72}
          .hljs-title,.hljs-title.class_,.hljs-title.class_.inherited__,.hljs-title.function_{color:#d2a8ff}
          .hljs-attr,.hljs-attribute,.hljs-literal,.hljs-meta,.hljs-number,.hljs-operator,.hljs-selector-attr,.hljs-selector-class,.hljs-selector-id,.hljs-variable{color:#79c0ff}
          .hljs-meta .hljs-string,.hljs-regexp,.hljs-string{color:#a5d6ff}
          .hljs-built_in,.hljs-symbol{color:#ffa657}
          .hljs-code,.hljs-comment,.hljs-formula{color:#8b949e}
          .hljs-name,.hljs-quote,.hljs-selector-pseudo,.hljs-selector-tag{color:#7ee787}
          .hljs-subst{color:#c9d1d9}
          .hljs-section{color:#1f6feb;font-weight:700}
          .hljs-bullet{color:#d2a8ff}
          .hljs-emphasis{color:#c9d1d9;font-style:italic}
          .hljs-strong{color:#c9d1d9;font-weight:700}
          .hljs-addition{color:#aff5b4;background:#033a16}
          .hljs-deletion{color:#ffdcd7;background:#67060c}
          }

          * { margin: 0; padding: 0; box-sizing: border-box; }

          :root {
            --bg: #ffffff;
            --text: #24292e;
            --border: #e1e4e8;
            --code-bg: #f6f8fa;
            --blockquote-border: #d0d7de;
            --blockquote-text: #57606a;
            --link: #0969da;
            --heading: #1f2328;
            --hr: #d0d7de;
            --table-bg: #f6f8fa;
            --table-border: #d0d7de;
          }

          @media (prefers-color-scheme: dark) {
            :root {
              --bg: #0d1117;
              --text: #c9d1d9;
              --border: #30363d;
              --code-bg: #161b22;
              --blockquote-border: #30363d;
              --blockquote-text: #8b949e;
              --link: #58a6ff;
              --heading: #e6edf3;
              --hr: #30363d;
              --table-bg: #161b22;
              --table-border: #30363d;
            }
          }

          body {
            font-family: -apple-system, BlinkMacSystemFont, 'SF Pro', 'Segoe UI', Helvetica, Arial, sans-serif;
            font-size: 15px;
            line-height: 1.7;
            color: var(--text);
            background: var(--bg);
            padding: 32px 40px;
            max-width: 900px;
            margin: 0 auto;
            -webkit-font-smoothing: antialiased;
          }

          h1, h2, h3, h4, h5, h6 {
            color: var(--heading);
            margin-top: 24px;
            margin-bottom: 16px;
            font-weight: 600;
            line-height: 1.25;
          }
          h1 { font-size: 2em; border-bottom: 1px solid var(--border); padding-bottom: 8px; }
          h2 { font-size: 1.5em; border-bottom: 1px solid var(--border); padding-bottom: 6px; }
          h3 { font-size: 1.25em; }
          h4 { font-size: 1em; }

          p { margin-bottom: 16px; }
          a { color: var(--link); text-decoration: none; }
          a:hover { text-decoration: underline; }

          ul, ol { padding-left: 2em; margin-bottom: 16px; }
          li { margin-bottom: 4px; }

          blockquote {
            margin: 0 0 16px;
            padding: 0 16px;
            color: var(--blockquote-text);
            border-left: 4px solid var(--blockquote-border);
          }

          code {
            font-family: 'SF Mono', Menlo, Consolas, monospace;
            font-size: 13px;
            padding: 2px 6px;
            border-radius: 4px;
            background: var(--code-bg);
            color: var(--text);
          }
          /* Code blocks inside <pre> get their background from .hljs */
          pre {
            margin-bottom: 16px;
            border-radius: 8px;
            overflow: hidden;
          }
          pre code {
            background: none;
            padding: 16px;
            display: block;
            overflow-x: auto;
            border: 1px solid var(--border);
            border-radius: 8px;
            font-size: 13px;
            line-height: 1.5;
          }

          hr {
            height: 1px;
            border: none;
            background: var(--hr);
            margin: 24px 0;
          }

          table { border-collapse: collapse; width: 100%; margin-bottom: 16px; }
          th, td { border: 1px solid var(--table-border); padding: 8px 12px; text-align: left; }
          th { background: var(--table-bg); font-weight: 600; }
          tr:nth-child(even) { background: var(--table-bg); }

          img { max-width: 100%; border-radius: 6px; }

          .mermaid-container { margin: 16px 0; display: flex; justify-content: center; }
          .mermaid-container svg { max-width: 100%; height: auto; }

          .error-block {
            color: #d73a49;
            background: var(--code-bg);
            border: 1px solid #d73a49;
            border-radius: 8px;
            padding: 12px 16px;
            font-family: 'SF Mono', Menlo, Consolas, monospace;
            font-size: 12px;
          }

          ::-webkit-scrollbar { width: 8px; }
          ::-webkit-scrollbar-track { background: transparent; }
          ::-webkit-scrollbar-thumb { background: var(--border); border-radius: 4px; }
        </style>
        </head>
        <body>
        <div id="content"></div>

        <script>
        (function() {
          try {
            var isDark = window.matchMedia('(prefers-color-scheme: dark)').matches;

            mermaid.initialize({
              startOnLoad: false,
              theme: isDark ? 'dark' : 'default'
            });

            var content = \(contentJSON);
            var diagrams = [];

            // Extract mermaid code blocks
            var processed = content.replace(/```mermaid[^]*?```/g, function(match) {
              var code = match.replace('```mermaid', '').slice(0, -3).trim();
              var id = 'm' + diagrams.length;
              diagrams.push({id: id, code: code});
              return '<div id=\"' + id + '\"></div>';
            });

            // Render markdown to HTML
            document.getElementById('content').innerHTML = marked.parse(processed, {
              breaks: true,
              gfm: true
            });

            // Highlight ALL code blocks using synchronous hljs.highlight() API
            document.querySelectorAll('pre code').forEach(function(block) {
              var lang = null;
              var match = block.className.match(/language-([a-zA-Z0-9_]+)/);
              if (match) { lang = match[1]; }

              // Apply known aliases BEFORE checking hljs (some languages like
              // 'shell' exist in hljs but are the wrong grammar — terminal
              // session output, not bash scripting)
              var aliasMap = {
                'shell': 'bash', 'sh': 'bash', 'zsh': 'bash',
                'js': 'javascript', 'jsx': 'javascript', 'mjs': 'javascript', 'cjs': 'javascript',
                'ts': 'typescript', 'tsx': 'typescript',
                'py': 'python', 'gyp': 'python',
                'rb': 'ruby', 'gemspec': 'ruby',
                'rs': 'rust',
                'go': 'go', 'golang': 'go',
                'c++': 'cpp', 'cc': 'cpp', 'cxx': 'cpp', 'hpp': 'cpp', 'hxx': 'cpp',
                'cs': 'csharp', 'c#': 'csharp',
                'kt': 'kotlin', 'kts': 'kotlin',
                'pl': 'perl', 'pm': 'perl',
                'md': 'markdown', 'mkdown': 'markdown', 'mkd': 'markdown',
                'yml': 'yaml',
                'html': 'xml', 'xhtml': 'xml', 'svg': 'xml',
                'make': 'makefile', 'mk': 'makefile', 'mak': 'makefile',
                'patch': 'diff',
                'gql': 'graphql',
                'toml': 'ini',
                'txt': 'plaintext', 'text': 'plaintext',
                'console': 'plaintext', 'shellsession': 'plaintext',
              };
              if (lang && aliasMap[lang]) { lang = aliasMap[lang]; }

              if (lang && hljs.getLanguage(lang)) {
                // Explicit language — use it
                var result = hljs.highlight(block.textContent, { language: lang, ignoreIllegals: true });
                block.innerHTML = result.value;
                block.classList.add('hljs');
              } else {
                // No language or unknown — auto-detect
                try {
                  var result = hljs.highlightAuto(block.textContent);
                  if (result.value) {
                    block.innerHTML = result.value;
                    block.classList.add('hljs');
                  }
                } catch(e) { /* auto-detect failed, leave as-is */ }
              }
            });

            // Render mermaid diagrams
            diagrams.forEach(function(d) {
              mermaid.render(d.id + 's', d.code).then(function(r) {
                var el = document.getElementById(d.id);
                if (el && r && r.svg) {
                  el.innerHTML = '<div class=\"mermaid-container\">' + r.svg + '</div>';
                }
              }).catch(function(e) {
                var el = document.getElementById(d.id);
                if (el) {
                  el.innerHTML = '<div class=\"error-block\">Mermaid: ' + String(e.message || e) + '</div>';
                }
              });
            });
          } catch(e) {
            document.getElementById('content').innerHTML = '<div class=\"error-block\">Render error: ' + String(e.message || e) + '</div>';
          }

          // Scroll sync — report scroll position to native
          window.addEventListener('scroll', function() {
            var docHeight = document.documentElement.scrollHeight - window.innerHeight;
            var percent = docHeight > 0 ? window.scrollY / docHeight : 0;
            window.webkit.messageHandlers.scrollHandler.postMessage({percent: percent});
          });
        })();
        </script>
        </body>
        </html>
        """
    }
}

// MARK: - Coordinator

extension MarkdownWebView {
    class Coordinator: NSObject {
        var lastLoadedContent: String = ""
        let previewDir: URL
        private var resourcesPrepared = false
        var onScrollChange: ((Double) -> Void)?
        var isProgrammaticScroll = false

        init(onScrollChange: ((Double) -> Void)? = nil) {
            self.onScrollChange = onScrollChange
            let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            previewDir = cachesDir.appendingPathComponent("com.markedit.preview", isDirectory: true)
        }

        /// Copy JS resource files to the preview directory (only once).
        func prepareResources() {
            guard !resourcesPrepared else { return }

            let fm = FileManager.default
            try? fm.createDirectory(at: previewDir, withIntermediateDirectories: true)

            // Copy marked.min.js from app bundle
            if let srcURL = Bundle.module.url(forResource: "marked.min", withExtension: "js", subdirectory: "Resources/Preview") {
                try? fm.copyItem(at: srcURL, to: previewDir.appendingPathComponent("marked.min.js"))
            }
            // Fallback: try main bundle
            if !fm.fileExists(atPath: previewDir.appendingPathComponent("marked.min.js").path),
               let srcURL = Bundle.main.url(forResource: "marked.min", withExtension: "js", subdirectory: "Preview") {
                try? fm.copyItem(at: srcURL, to: previewDir.appendingPathComponent("marked.min.js"))
            }

            // Copy highlight.min.js
            if let srcURL = Bundle.module.url(forResource: "highlight.min", withExtension: "js", subdirectory: "Resources/Preview") {
                try? fm.copyItem(at: srcURL, to: previewDir.appendingPathComponent("highlight.min.js"))
            }
            if !fm.fileExists(atPath: previewDir.appendingPathComponent("highlight.min.js").path),
               let srcURL = Bundle.main.url(forResource: "highlight.min", withExtension: "js", subdirectory: "Preview") {
                try? fm.copyItem(at: srcURL, to: previewDir.appendingPathComponent("highlight.min.js"))
            }

            // Copy mermaid.min.js
            if let srcURL = Bundle.module.url(forResource: "mermaid.min", withExtension: "js", subdirectory: "Resources/Preview") {
                try? fm.copyItem(at: srcURL, to: previewDir.appendingPathComponent("mermaid.min.js"))
            }
            if !fm.fileExists(atPath: previewDir.appendingPathComponent("mermaid.min.js").path),
               let srcURL = Bundle.main.url(forResource: "mermaid.min", withExtension: "js", subdirectory: "Preview") {
                try? fm.copyItem(at: srcURL, to: previewDir.appendingPathComponent("mermaid.min.js"))
            }

            resourcesPrepared = true
        }
    }
}

// MARK: - WKScriptMessageHandler

extension MarkdownWebView.Coordinator: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "scrollHandler",
              let body = message.body as? [String: Any],
              let percent = body["percent"] as? Double else { return }

        // Ignore scroll events triggered by programmatic scrollTo()
        if isProgrammaticScroll {
            isProgrammaticScroll = false
            return
        }

        onScrollChange?(percent)
    }
}
