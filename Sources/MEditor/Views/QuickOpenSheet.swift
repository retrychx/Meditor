import SwiftUI

/// Fuzzy file finder presented as a sheet over the main window.
/// Trigger via ⌘P.
///
/// Implementation notes:
/// - Searches all files in `state.fileItemMap` (which the file tree already
///   populates via depth-limited traversal). No async/Bg search needed for
///   the typical project size; if perf becomes an issue, we can move ranking
///   to a background task.
/// - Ranks results by simple substring + path depth. Good enough for now.
struct QuickOpenSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 13))
                TextField(L("quickOpen.placeholder"), text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($searchFocused)
                    .onSubmit { commitSelection() }
                    .onKeyPress(.upArrow) {
                        highlighted = max(0, highlighted - 1)
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        highlighted = min(results.count - 1, highlighted + 1)
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        dismiss()
                        return .handled
                    }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Results
            if results.isEmpty {
                emptyState
            } else {
                resultsList
            }
        }
        .frame(width: 520, height: 360)
        .onAppear {
            highlighted = 0
            searchFocused = true
        }
        .onChange(of: query) { _, _ in
            highlighted = 0
        }
    }

    // MARK: - Results

    private var results: [FileItem] {
        let allFiles = state.fileItemMap.values.filter { !$0.isDirectory }
        guard !query.isEmpty else {
            // Empty query: show recently used (open tabs first), then a-z by name.
            let openURLs = Set(state.openTabs.map { $0.url })
            let openFiles = allFiles.filter { openURLs.contains($0.url) }
            let others = allFiles
                .filter { !openURLs.contains($0.url) }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            return Array((openFiles + others).prefix(50))
        }
        return rank(allFiles, query: query)
    }

    /// Crude relevance ranking: prefers names that contain the query as a
    /// contiguous substring; ties broken by name length (shorter = better).
    private func rank(_ files: [FileItem], query: String) -> [FileItem] {
        let q = query.lowercased()
        let scored: [(FileItem, Int)] = files.compactMap { file in
            let name = file.name.lowercased()
            let path = file.url.path.lowercased()
            if name.hasPrefix(q) { return (file, 0) }
            if name.contains(q)  { return (file, 100 + name.count - q.count) }
            if path.contains(q)  { return (file, 1000 + path.count) }
            return nil
        }
        return scored
            .sorted { $0.1 < $1.1 }
            .prefix(50)
            .map { $0.0 }
    }

    private var resultsList: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(Array(results.enumerated()), id: \.element.id) { idx, item in
                    HStack(spacing: 8) {
                        Image(systemName: FileTypeConfiguration.shared.icon(for: item.fileExtension))
                            .foregroundStyle(.secondary)
                            .font(.system(size: 11))
                            .frame(width: 14)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.name)
                                .font(.system(size: 13))
                            Text(relativePath(for: item.url))
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .background(idx == highlighted ? Color.accentColor.opacity(0.18) : Color.clear)
                    .contentShape(Rectangle())
                    .id(idx)
                    .onTapGesture(count: 2) {
                        highlighted = idx
                        commitSelection()
                    }
                    .onTapGesture {
                        highlighted = idx
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .onChange(of: highlighted) { _, new in
                proxy.scrollTo(new, anchor: .center)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.tertiary)
            Text(query.isEmpty ? L("quickOpen.typeToSearch") : L("common.noMatches"))
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func commitSelection() {
        guard highlighted >= 0, highlighted < results.count else { return }
        state.openFile(results[highlighted])
        dismiss()
    }

    private func relativePath(for url: URL) -> String {
        guard let root = state.rootURL else { return url.lastPathComponent }
        let rootPath = root.path
        let path = url.path
        if path.hasPrefix(rootPath) {
            return String(path.dropFirst(rootPath.count).drop(while: { $0 == "/" }))
        }
        return path
    }
}
