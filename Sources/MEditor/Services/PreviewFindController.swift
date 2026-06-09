import AppKit
import Observation
import WebKit

@MainActor
@Observable
final class PreviewFindController {
    @ObservationIgnored
    private weak var markdownWebView: WKWebView?
    @ObservationIgnored
    private weak var htmlWebView: WKWebView?

    var activeMode: PreviewMode = .empty
    var isPresented = false
    var query = ""
    var hasMatch = true
    var focusToken = 0

    func register(webView: WKWebView?, for mode: PreviewMode) {
        switch mode {
        case .markdown:
            markdownWebView = webView
        case .html:
            htmlWebView = webView
        case .empty:
            break
        }
    }

    func show() {
        guard activeWebView != nil else { return }
        isPresented = true
        hasMatch = true
        focusToken &+= 1
    }

    func close() {
        isPresented = false
        hasMatch = true
    }

    func updateQuery(_ text: String) {
        query = text
        guard !text.isEmpty else {
            hasMatch = true
            return
        }
        runSearch(text, backwards: false, resetSelection: true)
    }

    func findNext() {
        guard ensurePresentedForSearch() else { return }
        guard !query.isEmpty else { return }
        runSearch(query, backwards: false, resetSelection: false)
    }

    func findPrevious() {
        guard ensurePresentedForSearch() else { return }
        guard !query.isEmpty else { return }
        runSearch(query, backwards: true, resetSelection: false)
    }

    func handleCommand(tag: Int) -> Bool {
        switch tag {
        case 1:
            guard activeWebView != nil else { return false }
            show()
            return true
        case 2:
            guard canHandleFindCommands else { return false }
            if query.isEmpty {
                show()
            } else {
                findNext()
            }
            return true
        case 3:
            guard canHandleFindCommands else { return false }
            if query.isEmpty {
                show()
            } else {
                findPrevious()
            }
            return true
        default:
            return false
        }
    }

    var canHandleFindCommands: Bool {
        if isPresented {
            return activeWebView != nil
        }
        guard let webView = activeWebView,
              let responder = NSApp.keyWindow?.firstResponder else {
            return false
        }
        if responder === webView {
            return true
        }
        guard let view = responder as? NSView else { return false }
        return view === webView || view.isDescendant(of: webView)
    }

    private var activeWebView: WKWebView? {
        switch activeMode {
        case .markdown:
            markdownWebView
        case .html:
            htmlWebView
        case .empty:
            nil
        }
    }

    private func ensurePresentedForSearch() -> Bool {
        guard activeWebView != nil else { return false }
        if !isPresented {
            show()
        }
        return true
    }

    private func runSearch(_ text: String, backwards: Bool, resetSelection: Bool) {
        guard let webView = activeWebView,
              let encoded = jsonEncode(text) else {
            hasMatch = false
            return
        }

        let js = """
        (function() {
            var text = \(encoded);
            if (!text) return true;
            if (\(resetSelection ? "true" : "false")) {
                try {
                    var selection = window.getSelection();
                    if (selection) {
                        selection.removeAllRanges();
                        var range = document.createRange();
                        var root = document.body || document.documentElement;
                        if (root) {
                            range.selectNodeContents(root);
                            range.collapse(\(backwards ? "false" : "true"));
                            selection.addRange(range);
                        }
                    }
                } catch (error) {}
            }
            return window.find(text, false, \(backwards ? "true" : "false"), true, false, true, false);
        })();
        """

        webView.evaluateJavaScript(js) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if error != nil {
                    self.hasMatch = false
                    return
                }
                self.hasMatch = (result as? Bool) ?? false
            }
        }
    }

    private func jsonEncode(_ string: String) -> String? {
        guard let data = try? JSONEncoder().encode(string) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
