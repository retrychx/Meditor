import SwiftUI
import WebKit
import MarkdownUI
import Splash

struct PreviewPanel: View {
    @Environment(AppState.self) private var state
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            if state.previewContent.isEmpty {
                emptyState
            } else if state.previewLanguage == .markdown {
                markdownPreview
            } else {
                htmlPreview
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: - Markdown Preview

    private var hasMermaid: Bool {
        state.previewContent.contains("```mermaid")
    }

    private var splashTheme: Splash.Theme {
        switch colorScheme {
        case .dark:
            return .wwdc18(withFont: .init(size: 13))
        default:
            return .wwdc17(withFont: .init(size: 13))
        }
    }

    @ViewBuilder
    private var markdownPreview: some View {
        if hasMermaid {
            // Use WKWebView + mermaid.js for mermaid blocks
            MermaidPreview(content: state.previewContent, splashTheme: splashTheme)
        } else {
            ScrollView {
                Markdown(state.previewContent)
                    .markdownTheme(.gitHub)
                    .markdownCodeSyntaxHighlighter(.splash(theme: splashTheme))
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - HTML Preview

    private var htmlPreview: some View {
        WebPreviewView(htmlContent: state.previewContent)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "eye")
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)
            Text("Preview")
                .foregroundStyle(.tertiary)
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Mermaid Preview (WKWebView)

private struct MermaidPreview: View {
    let content: String
    let splashTheme: Splash.Theme

    var body: some View {
        MermaidWebView(content: content, splashTheme: splashTheme)
    }
}

private struct MermaidWebView: NSViewRepresentable {
    let content: String
    let splashTheme: Splash.Theme

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.setValue(false, forKey: "drawsBackground")
        loadContent(into: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        loadContent(into: webView)
    }

    private func loadContent(into webView: WKWebView) {
        let html = buildHTML()
        webView.loadHTMLString(html, baseURL: URL(string: "about:blank")!)
    }

    private func buildHTML() -> String {
        // Safe escaping for JavaScript template literal
        let escaped = content
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "</script>", with: "<\\/script>")
            .replacingOccurrences(of: "</Script>", with: "<\\/Script>")

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="UTF-8">
        <style>
          :root { --bg: #fff; --text: #24292e; --border: #e1e4e8; --code-bg: #f6f8fa; }
          @media (prefers-color-scheme: dark) { :root { --bg: #0d1117; --text: #c9d1d9; --border: #30363d; --code-bg: #161b22; } }
          * { margin: 0; padding: 0; box-sizing: border-box; }
          body {
            font-family: -apple-system, BlinkMacSystemFont, 'SF Pro', sans-serif;
            font-size: 15px; line-height: 1.7; color: var(--text);
            background: var(--bg); padding: 32px 40px; max-width: 900px;
            margin: 0 auto; -webkit-font-smoothing: antialiased;
          }
          h1,h2,h3,h4,h5,h6 {
            margin: 24px 0 16px; font-weight: 600; line-height: 1.25;
          }
          h1 { font-size: 2em; border-bottom: 1px solid var(--border); padding-bottom: 8px; }
          h2 { font-size: 1.5em; border-bottom: 1px solid var(--border); padding-bottom: 6px; }
          p { margin-bottom: 16px; }
          a { color: #0969da; text-decoration: none; }
          ul, ol { padding-left: 2em; margin-bottom: 16px; }
          blockquote {
            margin: 0 0 16px; padding: 0 16px; border-left: 4px solid var(--border);
            color: #57606a;
          }
          code {
            font-family: 'SF Mono', Menlo, Consolas, monospace;
            font-size: 13px; padding: 2px 6px; background: var(--code-bg); border-radius: 4px;
          }
          pre { margin-bottom: 16px; border-radius: 8px; overflow: hidden; }
          pre code {
            padding: 16px; display: block; overflow-x: auto;
            background: var(--code-bg); border: 1px solid var(--border);
            border-radius: 8px; font-size: 13px; line-height: 1.5;
          }
          .mermaid-container { margin: 16px 0; display: flex; justify-content: center; }
          .mermaid-container svg { max-width: 100%; height: auto; }
        </style>
        </head>
        <body>
        <div id="content"></div>
        <script src="https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js"></script>
        <script src="https://cdn.jsdelivr.net/npm/marked@15/marked.min.js"></script>
        <script>
        (async function() {
          var isDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
          mermaid.initialize({ startOnLoad: false, theme: isDark ? 'dark' : 'default' });

          // Custom marked renderer: convert mermaid blocks to <div class="mermaid">
          var renderer = new marked.Renderer();
          renderer.code = function(code, lang) {
            if (lang === 'mermaid') {
              return '<div class="mermaid-container"><pre class="mermaid">' + code + '</pre></div>';
            }
            var cls = lang ? ' class="language-' + lang + '"' : '';
            return '<pre><code' + cls + '>' + code + '</code></pre>';
          };
          marked.setOptions({ breaks: true, gfm: true, renderer: renderer });

          var md = marked.parse(`\(escaped)`);
          document.getElementById('content').innerHTML = md;

          // Render all mermaid diagrams
          try {
            await mermaid.run({ querySelector: '.mermaid' });
          } catch(e) {
            console.error('Mermaid render error:', e);
          }
        })();
        </script>
        </body>
        </html>
        """
    }
}
