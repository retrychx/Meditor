import SwiftUI

/// 文档视图：编辑（TextEditor）与预览（Markdown 原生渲染 / HTML WebView）切换。
struct DocumentView: View {
    @Environment(DocumentStore.self) private var store

    var body: some View {
        NavigationStack {
            Group {
                if store.hasDocument {
                    content
                } else {
                    emptyState
                }
            }
            .background(PaperTheme.paper.ignoresSafeArea())
            .navigationTitle(store.hasDocument ? store.fileName : "MEditor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if store.hasDocument {
                    ToolbarItem(placement: .topBarTrailing) {
                        @Bindable var store = store
                        PaperSegmentedPicker(
                            items: [("编辑", false), ("预览", true)],
                            selection: $store.showPreview
                        )
                        .frame(width: 150)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        @Bindable var store = store
        if store.showPreview {
            switch store.kind {
            case .html:
                HTMLPreviewView(html: store.text)
            case .markdown:
                ScrollView {
                    Text(markdownStyled)
                        .lineSpacing(5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, PaperTheme.Spacing.page)
                        .padding(.vertical, 18)
                }
            case .other:
                ScrollView {
                    Text(store.text)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(PaperTheme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, PaperTheme.Spacing.page)
                        .padding(.vertical, 18)
                }
            }
        } else {
            TextEditor(text: $store.text)
                .font(PaperTheme.Typography.editorBody)
                .foregroundStyle(PaperTheme.ink)
                .lineSpacing(6)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 14)
                .padding(.top, 6)
        }
    }

    /// AttributedString 分段后自定义排版：标题换衬线、代码加浅色底。
    private var markdownStyled: AttributedString {
        let base = (try? AttributedString(markdown: store.text)) ?? AttributedString(store.text)
        var result = base
        result.foregroundColor = PaperTheme.ink

        for run in base.runs {
            if let intent = run.presentationIntent {
                for component in intent.components {
                    switch component.kind {
                    case .header(let level):
                        result[run.range].font = PaperTheme.Typography.heading(level: level)
                    case .codeBlock:
                        result[run.range].font = PaperTheme.Typography.code
                        result[run.range].backgroundColor = PaperTheme.codeBackground
                    case .blockQuote:
                        result[run.range].foregroundColor = PaperTheme.inkSecondary
                    default:
                        break
                    }
                }
            }
            if run.inlinePresentationIntent?.contains(.code) == true {
                result[run.range].font = .system(size: 15, design: .monospaced)
                result[run.range].backgroundColor = PaperTheme.codeBackground
            }
        }
        return result
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer()
            Image("BrandMark")
                .resizable()
                .scaledToFit()
                .frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(PaperTheme.hairline, lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.08), radius: 12, y: 4)

            Text("MEditor")
                .font(PaperTheme.Typography.brandTitle())
                .foregroundStyle(PaperTheme.ink)
                .padding(.top, 26)

            Text("纸墨之间，从容书写。")
                .font(PaperTheme.Typography.serifTitle3())
                .foregroundStyle(PaperTheme.inkSecondary)
                .padding(.top, 8)

            Text("在微信等 App 中打开 .md / .html 文件，选择「用其他应用打开」，即可发送到 MEditor 阅读、编辑，或与 AI 助手一起打磨。")
                .font(.subheadline)
                .foregroundStyle(PaperTheme.inkSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .frame(maxWidth: 300)
                .padding(.top, 16)

            if let error = store.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)
            }
            Spacer()
        }
        .padding(.horizontal, PaperTheme.Spacing.page)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
