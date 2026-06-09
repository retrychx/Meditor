import SwiftUI
import Combine

struct PreviewPanel: View {
    @Environment(AppState.self) private var state
    @State private var fontSize: Int = AppSettings.shared.previewFontSize
    @State private var tocItems: [TOCItem] = []
    @State private var activeTOCIndex: Int = -1
    @State private var scrollSync = ScrollSyncState()

    var body: some View {
        HStack(spacing: 0) {
            if showsMarkdown && !tocItems.isEmpty {
                TOCOutlineView(
                    items: tocItems,
                    activeLineIndex: activeTOCIndex,
                    onSelect: { item in
                        guard item.line >= 0 else { return }
                        if let idx = tocItems.firstIndex(where: { $0.id == item.id }) {
                            activeTOCIndex = idx
                        }
                        scrollSync.registerTOCNavigation()
                        state.requestEditorScroll(to: item.line)
                        state.requestPreviewScroll(to: item.line)
                    }
                )
                .frame(width: 220)
                .background(state.themeStore.current.chromeBackground.opacity(0.5))

                state.themeStore.current.separator
                    .frame(width: 1)
            }

            ZStack {
                MarkdownWebPreview(
                    content: showsMarkdown ? state.previewContent : "",
                    theme: state.themeStore.current,
                    scrollToLine: showsMarkdown ? state.previewScrollCommand.line : -1,
                    scrollRequestID: state.previewScrollCommand.nonce,
                    onVisibleLineChange: { line in
                        state.previewVisibleLine = line
                        let shouldPropagate = scrollSync.shouldPropagatePreviewScroll()
                        if shouldPropagate {
                            state.requestEditorScroll(to: line)
                        }
                        updateActiveTOC(visibleLine: line)
                    },
                    onTOCUpdate: { items in
                        tocItems = items
                        updateActiveTOC(visibleLine: state.previewVisibleLine)
                    },
                    exporter: state.previewExporter,
                    sourceURL: showsMarkdown ? state.selectedTab?.url : nil,
                    fontSize: fontSize,
                    findController: state.previewFindController
                )
                .opacity(showsMarkdown ? 1 : 0)
                .allowsHitTesting(showsMarkdown)

                WebPreviewView(
                    fileURL: showsHTML ? state.previewHTMLFileURL : nil,
                    reloadToken: state.previewReloadToken,
                    exporter: state.previewExporter,
                    rootURL: state.rootURL,
                    findController: state.previewFindController
                )
                .opacity(showsHTML ? 1 : 0)
                .allowsHitTesting(showsHTML)

                if state.previewMode == .empty {
                    emptyState
                        .background(Color(nsColor: .textBackgroundColor))
                }

                if state.previewFindController.isPresented && state.previewMode != .empty {
                    VStack {
                        HStack {
                            Spacer()
                            PreviewFindBar(
                                controller: state.previewFindController,
                                theme: state.themeStore.current
                            )
                        }
                        Spacer()
                    }
                    .padding(.top, 12)
                    .padding(.horizontal, 12)
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onAppear {
            state.previewFindController.activeMode = state.previewMode
        }
        .onChange(of: state.editorVisibleLine) { _, newLine in
            if scrollSync.shouldPropagateEditorScroll() {
                // Editor scroll drives preview scroll (normal editor↔preview sync)
                state.requestPreviewScroll(to: newLine)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .previewFontSizeChanged)) { _ in
            fontSize = AppSettings.shared.previewFontSize
        }
    }

    private var showsMarkdown: Bool { state.previewMode == .markdown }
    private var showsHTML: Bool { state.previewMode == .html }

    private func updateActiveTOC(visibleLine: Int) {
        guard !tocItems.isEmpty else { activeTOCIndex = -1; return }
        var best = -1
        for (idx, item) in tocItems.enumerated() {
            if item.line <= visibleLine { best = idx }
            else { break }
        }
        activeTOCIndex = best
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "eye")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.tertiary)
            Text(L("preview.empty"))
                .foregroundStyle(.tertiary)
                .font(.system(size: 12))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PreviewFindBar: View {
    @Bindable var controller: PreviewFindController
    let theme: PreviewTheme

    @FocusState private var fieldFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 11, weight: .medium))

            TextField(
                L("preview.findPlaceholder"),
                text: Binding(
                    get: { controller.query },
                    set: { controller.updateQuery($0) }
                )
            )
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .frame(width: 180)
            .focused($fieldFocused)
            .onSubmit {
                controller.findNext()
            }

            if !controller.hasMatch && !controller.query.isEmpty {
                Text(L("preview.findNoResults"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Button {
                controller.findPrevious()
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(L("menu.findPrevious"))

            Button {
                controller.findNext()
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(L("menu.findNext"))

            Button {
                controller.close()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(theme.chromeBackground.opacity(theme.isDark ? 0.96 : 0.98))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(theme.separator.opacity(theme.isDark ? 0.9 : 0.6), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: Color.black.opacity(theme.isDark ? 0.3 : 0.08), radius: 10, y: 4)
        .onAppear {
            fieldFocused = true
        }
        .onChange(of: controller.focusToken) { _, _ in
            fieldFocused = true
        }
    }
}
