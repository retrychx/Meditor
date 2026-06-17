import SwiftUI

struct SearchResultsPanel: View {
    @Environment(AppState.self) private var state

    @Binding var searchQuery: String
    let theme: PreviewTheme

    @State private var contentResults: [SearchPanelResult] = []
    @State private var isSearchingContent = false
    @State private var searchedContentQuery = ""
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            searchField

            if trimmedQuery.isEmpty {
                recentSection
            } else {
                resultsSections
            }
        }
        .onAppear {
            searchFocused = true
            scheduleContentSearch()
        }
        .onChange(of: searchQuery) { _, _ in scheduleContentSearch() }
        .onChange(of: state.indexedFiles.count) { _, _ in scheduleContentSearch() }
        .onDisappear {
            searchTask?.cancel()
            searchTask = nil
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.craftSecondary)

            TextField(L("rightPanel.search.placeholder"), text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(theme.craftPrimary)
                .focused($searchFocused)

            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.craftSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme.craftHover)
        )
    }

    @ViewBuilder
    private var recentSection: some View {
        let recent = recentResults
        if recent.isEmpty {
            placeholderPanel(
                title: L("rightPanel.search.emptyTitle"),
                message: L("rightPanel.search.emptyMessage")
            )
        } else {
            resultSection(title: L("rightPanel.search.recent"), results: recent)
        }
    }

    @ViewBuilder
    private var resultsSections: some View {
        let fileMatches = fileResults
        let currentContentResults = searchedContentQuery == normalizedQuery ? contentResults : []

        if fileMatches.isEmpty && currentContentResults.isEmpty && !isSearchingContent {
            placeholderPanel(
                title: L("common.noMatches"),
                message: L("rightPanel.search.noMatchesMessage")
            )
        } else {
            if !fileMatches.isEmpty {
                resultSection(title: L("rightPanel.search.files"), results: fileMatches)
            }

            if !currentContentResults.isEmpty || isSearchingContent {
                VStack(alignment: .leading, spacing: 6) {
                    sectionHeader(
                        title: L("rightPanel.search.content"),
                        isLoading: isSearchingContent
                    )

                    if currentContentResults.isEmpty {
                        Text(L("rightPanel.search.scanning"))
                            .font(.system(size: 11))
                            .foregroundStyle(theme.craftSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                    } else {
                        resultList(currentContentResults)
                    }
                }
            }
        }
    }

    private func resultSection(title: String, results: [SearchPanelResult]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader(title: title)
            resultList(results)
        }
    }

    private func resultList(_ results: [SearchPanelResult]) -> some View {
        VStack(spacing: 2) {
            ForEach(results) { result in
                SearchPanelResultRow(result: result, theme: theme)
            }
        }
    }

    private func sectionHeader(title: String, isLoading: Bool = false) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(theme.craftSecondary)
                .textCase(.uppercase)

            if isLoading {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.7)
            }
        }
        .padding(.top, 2)
        .padding(.horizontal, 2)
    }

    private func placeholderPanel(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.craftPrimary)

            Text(message)
                .font(.system(size: 11.5))
                .foregroundStyle(theme.craftSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var trimmedQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedQuery: String {
        trimmedQuery.lowercased()
    }

    private var searchableFiles: [FileItem] {
        state.indexedFiles.isEmpty
            ? state.fileItemMap.values.filter { !$0.isDirectory }
            : state.indexedFiles
    }

    private var recentResults: [SearchPanelResult] {
        let openURLs = Set(state.openTabs.map(\.url))
        return searchableFiles
            .filter { openURLs.contains($0.url) }
            .prefix(12)
            .map { item in
                SearchPanelResult(
                    kind: .file,
                    url: item.url,
                    name: item.name,
                    fileExtension: item.fileExtension,
                    relativePath: FilePathFormatter.relativePath(for: item.url, rootURL: state.rootURL),
                    line: nil,
                    snippet: nil
                )
            }
    }

    private var fileResults: [SearchPanelResult] {
        let query = normalizedQuery
        guard !query.isEmpty else { return [] }

        return searchableFiles.compactMap { item -> (SearchPanelResult, Int)? in
            let name = item.name.lowercased()
            let relativePath = FilePathFormatter.relativePath(for: item.url, rootURL: state.rootURL)
            let path = relativePath.lowercased()
            let score: Int

            if name.hasPrefix(query) {
                score = 0
            } else if name.contains(query) {
                score = 100 + name.count - query.count
            } else if path.contains(query) {
                score = 1000 + path.count
            } else {
                return nil
            }

            return (
                SearchPanelResult(
                    kind: .file,
                    url: item.url,
                    name: item.name,
                    fileExtension: item.fileExtension,
                    relativePath: relativePath,
                    line: nil,
                    snippet: nil
                ),
                score
            )
        }
        .sorted { lhs, rhs in lhs.1 < rhs.1 }
        .prefix(24)
        .map(\.0)
    }

    private func scheduleContentSearch() {
        searchTask?.cancel()
        contentResults = []
        searchedContentQuery = ""

        let query = normalizedQuery
        guard query.count >= 2 else {
            isSearchingContent = false
            return
        }

        let files = searchableFiles.map { item in
            SearchableFile(
                url: item.url,
                name: item.name,
                fileExtension: item.fileExtension,
                relativePath: FilePathFormatter.relativePath(for: item.url, rootURL: state.rootURL)
            )
        }

        isSearchingContent = true
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }

            let results = await Task.detached(priority: .utility) {
                SearchContentScanner.scan(files: files, query: query)
            }.value

            guard !Task.isCancelled else { return }
            searchedContentQuery = query
            contentResults = results
            isSearchingContent = false
        }
    }
}

private struct SearchPanelResult: Identifiable, Equatable, Sendable {
    enum Kind: Sendable {
        case file
        case content
    }

    let kind: Kind
    let url: URL
    let name: String
    let fileExtension: String
    let relativePath: String
    let line: Int?
    let snippet: String?

    var id: String {
        switch kind {
        case .file:
            return "file:\(url.absoluteString)"
        case .content:
            return "content:\(url.absoluteString):\(line ?? -1):\(snippet ?? "")"
        }
    }
}

private struct SearchPanelResultRow: View {
    @Environment(AppState.self) private var state

    let result: SearchPanelResult
    let theme: PreviewTheme

    @State private var isHovered = false

    private var isSelected: Bool {
        state.selectedTab?.url == result.url || state.selectedFileID == result.url
    }

    var body: some View {
        Button {
            openResult()
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: FileTypeConfiguration.shared.icon(for: result.fileExtension))
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: FileTypeConfiguration.shared.color(for: result.fileExtension)).opacity(0.78))
                    .frame(width: 14)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(result.name)
                            .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(theme.craftPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        if let line = result.line {
                            Text("L\(line + 1)")
                                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(theme.craftSecondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(theme.craftHover))
                        }
                    }

                    Text(result.relativePath)
                        .font(.system(size: 10))
                        .foregroundStyle(theme.craftSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if let snippet = result.snippet {
                        Text(snippet)
                            .font(.system(size: 10.5))
                            .foregroundStyle(theme.craftPrimary.opacity(0.72))
                            .lineLimit(2)
                            .truncationMode(.tail)
                            .padding(.top, 1)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, result.snippet == nil ? 6 : 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected ? Color.appAccent.opacity(0.12) : isHovered ? theme.craftHover : Color.clear)
        )
        .overlay(alignment: .leading) {
            if isSelected {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Color.appAccent.opacity(0.8))
                    .frame(width: 2)
                    .padding(.vertical, 5)
            }
        }
        .onHover { isHovered = $0 }
        .animation(DS.Motion.micro, value: isHovered)
        .animation(DS.Motion.micro, value: isSelected)
    }

    private func openResult() {
        state.openFile(FileItem(url: result.url, isDirectory: false))
        guard let line = result.line else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            state.requestEditorScroll(to: line)
            state.requestPreviewScroll(to: line)
        }
    }
}

private struct SearchableFile: Sendable {
    let url: URL
    let name: String
    let fileExtension: String
    let relativePath: String
}

private enum SearchContentScanner {
    private static let maxFilesToScan = 240
    private static let maxResults = 60
    private static let maxFileBytes = 512 * 1024

    static func scan(files: [SearchableFile], query: String) -> [SearchPanelResult] {
        guard query.count >= 2 else { return [] }

        var results: [SearchPanelResult] = []
        for file in files.prefix(maxFilesToScan) {
            if results.count >= maxResults { break }
            guard canScan(file.url),
                  let data = try? Data(contentsOf: file.url, options: .mappedIfSafe),
                  let text = TextFileDecoder.decode(data),
                  let match = firstMatch(in: text, query: query) else { continue }

            results.append(SearchPanelResult(
                kind: .content,
                url: file.url,
                name: file.name,
                fileExtension: file.fileExtension,
                relativePath: file.relativePath,
                line: match.line,
                snippet: match.snippet
            ))
        }

        return results
    }

    private static func canScan(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
              values.isRegularFile == true,
              let size = values.fileSize else { return false }
        return size <= maxFileBytes
    }

    private static func firstMatch(in text: String, query: String) -> (line: Int, snippet: String)? {
        for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let lineText = String(line)
            guard lineText.lowercased().contains(query) else { continue }
            return (index, snippet(for: lineText))
        }
        return nil
    }

    private static func snippet(for line: String) -> String {
        let collapsed = line
            .replacingOccurrences(of: "\t", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")

        guard collapsed.count > 160 else { return collapsed }
        let end = collapsed.index(collapsed.startIndex, offsetBy: 160)
        return String(collapsed[..<end]) + "..."
    }
}
