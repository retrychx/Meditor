import Foundation

/// Tool execution context — passed to every AgentTool.execute().
/// Provides controlled access to app state so tools can read/write the document.
@MainActor
final class AgentContext {
    weak var appState: AppState?

    init(appState: AppState) {
        self.appState = appState
    }

    // MARK: - Document access

    var currentDocument: String? { appState?.selectedTab?.content }
    var currentDocumentName: String? { appState?.selectedTab?.name }
    var workspaceURL: URL? { appState?.rootURL }

    func writeDocument(_ content: String) {
        guard let tab = appState?.selectedTab else { return }
        tab.content = content
        tab.contentRevision &+= 1
        appState?.scheduleDebounceSave()
    }

    func insertIntoDocument(_ text: String) {
        appState?.insertIntoEditor(text)
    }

    func listWorkspaceFiles(extensions: [String] = []) -> [URL] {
        guard let root = workspaceURL else { return [] }
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return enumerator.compactMap { item -> URL? in
            guard let url = item as? URL,
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            else { return nil }
            if extensions.isEmpty { return url }
            return extensions.contains(url.pathExtension.lowercased()) ? url : nil
        }
    }

    func readFile(at url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }
}
