import SwiftUI

struct RightPanelHost: View {
    @Environment(AppState.self) private var state
    @Bindable var workspaceUI: WorkspaceUIState
    @State private var searchQuery = ""

    private var theme: PreviewTheme { state.themeStore.current }

    var body: some View {
        if let panel = workspaceUI.rightPanel {
            VStack(spacing: 0) {
                header(for: panel)

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        content(for: panel)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollContentBackground(.hidden)
            }
            .frame(width: 292)
            .background(theme.chromeBackground.opacity(theme.isDark ? 0.82 : 0.94))
            .overlay(alignment: .leading) {
                theme.separator
                    .opacity(theme.isDark ? 0.44 : 0.24)
                    .frame(width: 1)
            }
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }

    private func header(for panel: WorkspaceUIState.RightPanelKind) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon(for: panel))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.craftSecondary)
                .frame(width: 16)

            Text(title(for: panel))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.craftPrimary)

            Spacer()

            ChromeButton(systemName: "xmark", help: L("common.close")) {
                withAnimation(DS.Motion.fast) {
                    workspaceUI.closeRightPanel()
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
        .background(theme.chromeBackground)
        .overlay(alignment: .bottom) {
            theme.separator
                .opacity(theme.isDark ? 0.44 : 0.2)
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private func content(for panel: WorkspaceUIState.RightPanelKind) -> some View {
        switch panel {
        case .insert:
            insertPanel
        case .pageInfo:
            pageInfoPanel
        case .comments:
            CommentsPanel(theme: theme)
        case .share:
            sharePanel
        case .search:
            searchPanel
        }
    }

    private var insertPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            panelNote(L("rightPanel.insert.message"))

            Button {
                state.templateCreateParentURL = state.rootURL
                state.showingTemplatePicker = true
            } label: {
                Label(L("menu.newFile"), systemImage: "square.and.pencil")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(state.rootURL == nil)

            Button {
                state.showingSaveTemplate = true
            } label: {
                Label(L("menu.saveAsTemplate"), systemImage: "doc.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(state.selectedTab == nil)
        }
    }

    private var outlinePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            let items = markdownOutlineItems
            if items.isEmpty {
                placeholderPanel(
                    title: L("rightPanel.outline.emptyTitle"),
                    message: L("rightPanel.outline.emptyMessage")
                )
            } else {
                let activeLine = activeOutlineLine(in: items)
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(items) { item in
                        OutlineResultRow(
                            item: item,
                            theme: theme,
                            isActive: item.line == activeLine
                        )
                    }
                }
            }
        }
    }

    private var pageInfoPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let tab = state.selectedTab {
                infoRow(L("rightPanel.info.name"), tab.name)
                infoRow(L("rightPanel.info.path"), pathText(tab.url))
                infoRow(L("rightPanel.info.language"), languageText(tab))
                infoRow(L("rightPanel.info.size"), state.currentFileSize)
                infoRow(L("rightPanel.info.words"), "\(wordCount(tab.content))")
                infoRow(L("rightPanel.info.modified"), tab.isModified ? L("common.yes") : L("common.no"))
            } else {
                placeholderPanel(
                    title: L("rightPanel.info.emptyTitle"),
                    message: L("rightPanel.info.emptyMessage")
                )
            }
        }
    }

    private var sharePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            if state.shareServer.isRunning {
                // The base host:port alone returns 404 — a working link must carry
                // the access token and file path, so surface the *current file's*
                // full URL via shareURLForFile.
                let fullURL = state.selectedTab
                    .flatMap { state.shareServer.shareURLForFile($0.url) }

                if let tab = state.selectedTab {
                    infoRow(L("share.currentFile"), tab.name)
                }
                infoRow(L("share.active"), fullURL ?? state.shareServer.shareURL)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(fullURL ?? state.shareServer.shareURL, forType: .string)
                } label: {
                    Label(L("share.copyURL"), systemImage: "link")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(fullURL == nil)

                Button(role: .destructive) {
                    state.shareServer.stop()
                } label: {
                    Label(L("share.stop"), systemImage: "wifi.slash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            } else {
                panelNote(L("rightPanel.share.message"))
                Button {
                    state.shareServer.start(
                        rootURL: state.rootURL,
                        openTabs: state.openTabs,
                        preferredPort: AppSettings.shared.sharePort
                    )
                } label: {
                    Label(L("share.viaLAN"), systemImage: "wifi")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(state.openTabs.isEmpty)
            }
        }
    }

    private var searchPanel: some View {
        SearchResultsPanel(searchQuery: $searchQuery, theme: theme)
    }

    private var markdownOutlineItems: [TOCItem] {
        guard let tab = state.selectedTab, tab.language == .markdown else { return [] }
        return parseMarkdownOutline(tab.content)
    }

    private func activeOutlineLine(in items: [TOCItem]) -> Int {
        var activeLine = -1
        for item in items {
            if item.line <= state.editorVisibleLine {
                activeLine = item.line
            } else {
                break
            }
        }
        return activeLine
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

    private func panelNote(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(theme.craftSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(theme.craftSecondary)
                .textCase(.uppercase)

            Text(value.isEmpty ? "-" : value)
                .font(.system(size: 12))
                .foregroundStyle(theme.craftPrimary)
                .lineLimit(3)
                .textSelection(.enabled)
        }
    }

    private func title(for panel: WorkspaceUIState.RightPanelKind) -> String {
        switch panel {
        case .insert:
            return L("rightPanel.insert")
        case .pageInfo:
            return L("rightPanel.pageInfo")
        case .comments:
            return L("rightPanel.comments")
        case .share:
            return L("rightPanel.share")
        case .search:
            return L("rightPanel.search")
        }
    }

    private func icon(for panel: WorkspaceUIState.RightPanelKind) -> String {
        switch panel {
        case .insert:
            return "plus"
        case .pageInfo:
            return "info.circle"
        case .comments:
            return "bubble.left"
        case .share:
            return "wifi"
        case .search:
            return "text.magnifyingglass"
        }
    }

    private func pathText(_ url: URL) -> String {
        guard let rootURL = state.rootURL else { return url.path }
        return FilePathFormatter.relativePath(for: url, rootURL: rootURL)
    }

    private func languageText(_ tab: EditorTab) -> String {
        FileTypeConfiguration.shared
            .editorLanguage(for: tab.url.pathExtension.lowercased())?.rawValue
            .capitalized ?? "Text"
    }

    private func wordCount(_ text: String) -> Int {
        var count = 0
        text.enumerateSubstrings(
            in: text.startIndex...,
            options: [.byWords, .substringNotRequired]
        ) { _, _, _, _ in
            count += 1
        }
        return count
    }

    private func parseMarkdownOutline(_ content: String) -> [TOCItem] {
        var items: [TOCItem] = []
        var isInFence = false

        for (lineIndex, lineSlice) in content.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = String(lineSlice)
            let trimmedLeading = line.drop { $0 == " " || $0 == "\t" }

            if trimmedLeading.hasPrefix("```") || trimmedLeading.hasPrefix("~~~") {
                isInFence.toggle()
                continue
            }

            guard !isInFence, trimmedLeading.hasPrefix("#") else { continue }

            let level = trimmedLeading.prefix(while: { $0 == "#" }).count
            guard (1...6).contains(level) else { continue }
            let afterHashes = trimmedLeading.dropFirst(level)
            guard afterHashes.first == " " || afterHashes.first == "\t" else { continue }

            let rawTitle = afterHashes
                .drop { $0 == " " || $0 == "\t" }
                .trimmingTrailingMarkdownHeadingMarkers()
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !rawTitle.isEmpty else { continue }
            items.append(TOCItem(level: level, title: rawTitle, line: lineIndex))
        }

        return items
    }
}

private struct OutlineResultRow: View {
    @Environment(AppState.self) private var state

    let item: TOCItem
    let theme: PreviewTheme
    let isActive: Bool

    @State private var isHovered = false

    var body: some View {
        Button {
            state.requestEditorScroll(to: item.line)
            state.requestPreviewScroll(to: item.line)
        } label: {
            HStack(alignment: .top, spacing: 0) {
                Color.clear
                    .frame(width: CGFloat((item.level - 1).clamped(to: 0...5)) * 10)

                Text(item.title)
                    .font(.system(size: fontSize, weight: fontWeight))
                    .foregroundStyle(isActive ? theme.craftPrimary : theme.craftSecondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, verticalPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(isActive ? Color.accentColor.opacity(0.12) : isHovered ? theme.craftHover : Color.clear)
                    )
                    .overlay(alignment: .leading) {
                        if isActive || item.level >= 3 {
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .fill(isActive ? Color.accentColor.opacity(0.78) : theme.craftSecondary.opacity(0.18))
                                .frame(width: isActive ? 2.5 : 1)
                                .padding(.vertical, 5)
                        }
                    }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(DS.Motion.micro, value: isHovered)
        .animation(DS.Motion.micro, value: isActive)
    }

    private var fontSize: CGFloat {
        switch item.level {
        case 1: return 12.5
        case 2: return 11.5
        default: return 10.5
        }
    }

    private var fontWeight: Font.Weight {
        if isActive { return .semibold }
        switch item.level {
        case 1: return .semibold
        case 2: return .medium
        default: return .regular
        }
    }

    private var verticalPadding: CGFloat {
        switch item.level {
        case 1: return 7
        case 2: return 6
        default: return 5
        }
    }
}

private extension StringProtocol {
    func trimmingTrailingMarkdownHeadingMarkers() -> String {
        let trimmed = String(self).trimmingCharacters(in: .whitespaces)
        guard trimmed.last == "#" else { return trimmed }

        var markerStart = trimmed.endIndex
        while markerStart > trimmed.startIndex {
            let previous = trimmed.index(before: markerStart)
            guard trimmed[previous] == "#" else { break }
            markerStart = previous
        }

        guard markerStart > trimmed.startIndex else { return trimmed }
        let beforeMarkers = trimmed.index(before: markerStart)
        guard trimmed[beforeMarkers].isWhitespace else { return trimmed }

        return String(trimmed[..<markerStart]).trimmingCharacters(in: .whitespaces)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
