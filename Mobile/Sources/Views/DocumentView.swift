import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 文档视图：编辑（TextEditor）与预览（Markdown 原生渲染 / HTML WebView）切换。
struct DocumentView: View {
    @Environment(DocumentStore.self) private var store

    @State private var showingFilePicker = false
    @State private var showingAIChat = false
    @State private var showingOpenError = false

    /// 可导入的文件类型：Markdown / HTML / 纯文本。
    private static let importableTypes: [UTType] = [
        .plainText, .html,
        UTType(filenameExtension: "md"),
        UTType(filenameExtension: "markdown"),
    ].compactMap { $0 }

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
                    ToolbarItem(placement: .topBarLeading) {
                        Button { showingFilePicker = true } label: {
                            Image(systemName: "folder")
                                .font(.system(size: 15))
                                .foregroundStyle(PaperTheme.inkSecondary)
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 10) {
                            modeToggle
                            documentMenu
                        }
                    }
                }
            }
            // 文档打开时：右下角悬浮 AI 钮
            .overlay(alignment: .bottomTrailing) {
                if store.hasDocument {
                    aiFab
                        .padding(.trailing, 20)
                        .padding(.bottom, 16)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: store.hasDocument)
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: Self.importableTypes,
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                store.openIncoming(url)
            }
        }
        .sheet(isPresented: $showingAIChat) {
            AIChatView()
        }
        // 打开失败：无论空态还是已有文档，都明确弹窗告知（真机权限/iCloud 问题全靠它暴露）
        .onChange(of: store.lastError) { _, newValue in
            showingOpenError = newValue != nil
        }
        .alert("无法打开文件", isPresented: $showingOpenError) {
            Button("好", role: .cancel) { store.lastError = nil }
        } message: {
            Text(store.lastError ?? "")
        }
    }

    /// 悬浮 AI 钮：单钮 FAB，强调色底 + 同色柔投影。
    private var aiFab: some View {
        Button { showingAIChat = true } label: {
            Image(systemName: "sparkles")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 50, height: 50)
                .background(PaperTheme.accent, in: Circle())
                .overlay { Circle().strokeBorder(.white.opacity(0.25), lineWidth: 0.5) }
                .shadow(color: PaperTheme.accent.opacity(0.35), radius: 14, y: 6)
        }
        .accessibilityLabel("AI 助手")
    }

    /// 单钮模式切换：预览态显示铅笔（点去编辑），编辑态显示文档（点去预览）。
    /// 普通 toolbar 按钮，和左侧文件夹钮、右侧 ⋯ 共享同一套系统玻璃圆形样式。
    private var modeToggle: some View {
        Button {
            store.showPreview.toggle()
        } label: {
            Image(systemName: store.showPreview ? "pencil" : "doc.richtext")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(PaperTheme.inkSecondary)
                .contentTransition(.symbolEffect(.replace.downUp))
        }
        .accessibilityLabel(store.showPreview ? "编辑" : "预览")
    }

    /// 导航栏「⋯」菜单：分享 / 复制等文档级操作的归宿。
    private var documentMenu: some View {
        Menu {
            ShareLink(item: store.text, subject: Text(store.fileName)) {
                Label("分享全文", systemImage: "square.and.arrow.up")
            }
            Button {
                UIPasteboard.general.string = store.text
            } label: {
                Label("复制全文", systemImage: "doc.on.doc")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(PaperTheme.inkSecondary)
        }
    }

    @ViewBuilder
    private var content: some View {
        if store.showPreview {
            switch store.kind {
            case .html:
                HTMLPreviewView(html: store.text)
            case .markdown:
                MarkdownPreviewView(source: store.text)
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
            // 手动编辑经 applyManualEdit 进 store：触发防抖自动保存，进程退出不丢内容。
            TextEditor(text: Binding(
                get: { store.text },
                set: { store.applyManualEdit($0) }
            ))
                .font(PaperTheme.Typography.editorBody)
                .foregroundStyle(PaperTheme.ink)
                .lineSpacing(6)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 14)
                .padding(.top, 6)
        }
    }

    /// 空态：品牌标识 + 打开文件入口。
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

            Text("从文件 App 选择 .md / .html 打开，或在微信等 App 中选择「用其他应用打开」发送到 MEditor。")
                .font(.subheadline)
                .foregroundStyle(PaperTheme.inkSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .frame(maxWidth: 300)
                .padding(.top, 16)

            Button {
                showingFilePicker = true
            } label: {
                Label("打开文件", systemImage: "folder")
            }
            .buttonStyle(.paperPrimary)
            .padding(.top, 26)

            Spacer()
        }
        .padding(.horizontal, PaperTheme.Spacing.page)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
