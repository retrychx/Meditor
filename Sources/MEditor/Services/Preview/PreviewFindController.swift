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
    @ObservationIgnored
    private var pendingSearchWorkItem: DispatchWorkItem?

    private static let searchDebounce: TimeInterval = 0.15

    var activeMode: PreviewMode = .empty
    var isPresented = false
    var query = ""
    var hasMatch = true
    var focusToken = 0
    var matchCount = 0
    var currentMatchIndex = 0

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
        if query.isEmpty {
            hasMatch = true
            matchCount = 0
            currentMatchIndex = 0
        }
        focusToken &+= 1
    }

    func close() {
        cancelPendingSearch()
        clearSearchSelection()
        isPresented = false
        hasMatch = true
        matchCount = 0
        currentMatchIndex = 0
    }

    func updateQuery(_ text: String) {
        query = text
        cancelPendingSearch()
        guard !text.isEmpty else {
            hasMatch = true
            matchCount = 0
            currentMatchIndex = 0
            clearSearchSelection()
            return
        }
        scheduleSearch(text, backwards: false, resetSelection: true)
    }

    func findNext() {
        guard ensurePresentedForSearch() else { return }
        guard !query.isEmpty else { return }
        cancelPendingSearch()
        runSearch(query, backwards: false, resetSelection: false)
    }

    func findPrevious() {
        guard ensurePresentedForSearch() else { return }
        guard !query.isEmpty else { return }
        cancelPendingSearch()
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

    private func scheduleSearch(_ text: String, backwards: Bool, resetSelection: Bool) {
        var workItem: DispatchWorkItem!
        workItem = DispatchWorkItem { [weak self] in
            guard workItem.isCancelled == false else { return }
            self?.runSearch(text, backwards: backwards, resetSelection: resetSelection)
        }
        pendingSearchWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.searchDebounce, execute: workItem)
    }

    private func cancelPendingSearch() {
        pendingSearchWorkItem?.cancel()
        pendingSearchWorkItem = nil
    }

    private func runSearch(_ text: String, backwards: Bool, resetSelection: Bool) {
        pendingSearchWorkItem = nil
        guard let webView = activeWebView,
              let encoded = jsonEncode(text) else {
            hasMatch = false
            matchCount = 0
            currentMatchIndex = 0
            return
        }

        let js = """
        (function() {
            var text = \(encoded);
            var root = document.body || document.documentElement;
            var selection = window.getSelection();
            var emptyResult = { count: 0, current: 0 };
            var state = window.__meditorFindState || { query: '', currentIndex: -1, count: 0 };

            function clearSelection() {
                try {
                    if (selection) selection.removeAllRanges();
                } catch (error) {}
            }

            function createWalker() {
                return document.createTreeWalker(
                    root,
                    NodeFilter.SHOW_TEXT,
                    {
                        acceptNode: function(node) {
                            if (!node || !node.nodeValue || !node.nodeValue.trim()) {
                                return NodeFilter.FILTER_REJECT;
                            }
                            var parent = node.parentNode;
                            if (!parent || !parent.tagName) return NodeFilter.FILTER_ACCEPT;
                            var tag = parent.tagName.toLowerCase();
                            if (tag === 'script' || tag === 'style' || tag === 'noscript') {
                                return NodeFilter.FILTER_REJECT;
                            }
                            return NodeFilter.FILTER_ACCEPT;
                        }
                    }
                );
            }

            function countMatches(queryLower) {
                var walker = createWalker();
                var node;
                var total = 0;
                var step = Math.max(1, queryLower.length);
                while ((node = walker.nextNode())) {
                    var lower = node.nodeValue.toLowerCase();
                    var start = 0;
                    while (true) {
                        var index = lower.indexOf(queryLower, start);
                        if (index === -1) break;
                        total += 1;
                        start = index + step;
                    }
                }
                return total;
            }

            function selectMatch(queryLower, targetIndex) {
                var walker = createWalker();
                var node;
                var seen = 0;
                var step = Math.max(1, queryLower.length);

                while ((node = walker.nextNode())) {
                    var lower = node.nodeValue.toLowerCase();
                    var start = 0;
                    while (true) {
                        var index = lower.indexOf(queryLower, start);
                        if (index === -1) break;
                        if (seen === targetIndex) {
                            var range = document.createRange();
                            range.setStart(node, index);
                            range.setEnd(node, index + text.length);
                            clearSelection();
                            if (selection) selection.addRange(range);
                            var rect = range.getBoundingClientRect();
                            if (rect && (rect.top < 0 || rect.bottom > window.innerHeight)) {
                                var top = window.scrollY + rect.top - Math.max(80, window.innerHeight * 0.2);
                                window.scrollTo({ top: Math.max(0, top), behavior: 'auto' });
                            }
                            return true;
                        }
                        seen += 1;
                        start = index + step;
                    }
                }
                return false;
            }

            if (!text || !root) {
                clearSelection();
                window.__meditorFindState = { query: '', currentIndex: -1, count: 0 };
                return emptyResult;
            }

            var queryLower = text.toLowerCase();
            var total = countMatches(queryLower);
            if (total === 0) {
                clearSelection();
                window.__meditorFindState = { query: text, currentIndex: -1, count: 0 };
                return emptyResult;
            }

            var queryChanged = state.query !== text;
            var targetIndex;
            if (queryChanged || \(resetSelection ? "true" : "false") || state.currentIndex < 0 || state.currentIndex >= total) {
                targetIndex = \(backwards ? "total - 1" : "0");
            } else if (\(backwards ? "true" : "false")) {
                targetIndex = state.currentIndex - 1;
                if (targetIndex < 0) targetIndex = total - 1;
            } else {
                targetIndex = state.currentIndex + 1;
                if (targetIndex >= total) targetIndex = 0;
            }

            selectMatch(queryLower, targetIndex);
            window.__meditorFindState = { query: text, currentIndex: targetIndex, count: total };
            return { count: total, current: targetIndex + 1 };
        })();
        """

        webView.evaluateJavaScript(js) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if error != nil {
                    self.hasMatch = false
                    self.matchCount = 0
                    self.currentMatchIndex = 0
                    return
                }
                let payload = result as? [String: Any]
                let count = payload?["count"] as? Int ?? 0
                let current = payload?["current"] as? Int ?? 0
                self.matchCount = count
                self.currentMatchIndex = current
                self.hasMatch = count > 0
            }
        }
    }

    private func clearSearchSelection() {
        guard let webView = activeWebView else { return }
        let js = """
        (function() {
            try {
                var selection = window.getSelection();
                if (selection) selection.removeAllRanges();
            } catch (error) {}
            window.__meditorFindState = { query: '', currentIndex: -1, count: 0 };
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private func jsonEncode(_ string: String) -> String? {
        guard let data = try? JSONEncoder().encode(string) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
