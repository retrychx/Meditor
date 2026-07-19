import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 文档视图：编辑（TextEditor）与预览（Markdown 原生渲染 / HTML WebView）切换。
struct DocumentView: View {
    @Environment(DocumentStore.self) private var store

    @State private var showingFilePicker = false
    @State private var showingAIChat = false
    @State private var showingOpenError = false
    /// 预览滚动越顶：导航栏从透明过渡到纸底 + 发丝分隔。
    @State private var contentScrolled = false
    /// 空态入场动画开关。
    @State private var emptyStateVisible = false
    /// FAB：下滚收起、回滚唤回。
    @State private var fabHidden = false
    @State private var lastScrollY: CGFloat = 0
    /// 空态印章「盖下」动画开关。
    @State private var sealStamped = false

    /// 可导入的文件类型：Markdown / HTML / 纯文本。
    private static let importableTypes: [UTType] = [
        .plainText, .html,
        UTType(filenameExtension: "md"),
        UTType(filenameExtension: "markdown"),
    ].compactMap { $0 }

    /// 顶部是否透明：空态、或预览未滚动时透明；滚动 / 编辑态回到纸底。
    private var transparentHeader: Bool {
        store.hasDocument ? (store.showPreview && !contentScrolled) : true
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.hasDocument {
                    content
                        .id(store.showPreview)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.98)).combined(with: .offset(y: 8)),
                            removal: .opacity
                        ))
                } else {
                    emptyState
                }
            }
            .animation(PaperTheme.Motion.standard, value: store.showPreview)
            .background(PaperTheme.paper.ignoresSafeArea())
            .navigationTitle(store.hasDocument ? store.fileName : "MEditor")
            .navigationBarTitleDisplayMode(.inline)
            // 透明 ↔ 纸底的过渡随滚动状态缓动
            .toolbarBackground(transparentHeader ? .hidden : .visible, for: .navigationBar)
            .animation(PaperTheme.Motion.gentle, value: transparentHeader)
            .onPreferenceChange(PreviewScrollOffsetKey.self) { minY in
                contentScrolled = minY < -8
                // 下滚（minY 变小）收 FAB，回滚唤回；6pt 滞回防抖
                let delta = minY - lastScrollY
                if delta < -6 { fabHidden = true }
                else if delta > 6 { fabHidden = false }
                lastScrollY = minY
            }
            .toolbar {
                // 标题自绘：文档文件名 / 品牌字保留衬线（UI chrome 其余部分是无衬线）。
                ToolbarItem(placement: .principal) {
                    Text(store.hasDocument ? store.fileName : "MEditor")
                        .font(.system(.headline, design: .serif, weight: .semibold))
                        .foregroundStyle(PaperTheme.ink)
                        .lineLimit(1)
                }
                if store.hasDocument {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { showingFilePicker = true } label: {
                            Image(systemName: "folder")
                                .font(.system(size: 15))
                                .foregroundStyle(PaperTheme.inkSecondary)
                        }
                        .buttonStyle(.pressable)
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
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                }
            }
            .animation(PaperTheme.Motion.standard, value: store.hasDocument)
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

    /// 悬浮 AI 钮：单钮 FAB，朱砂底 + 同色柔投影；图标微光闪烁，
    /// 下滚缩小收起、回滚唤回。
    private var aiFab: some View {
        Button { showingAIChat = true } label: {
            Image(systemName: "sparkles")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .symbolEffect(.variableColor.iterative, options: .repeating)
                .frame(width: 50, height: 50)
                .background(PaperTheme.accent, in: Circle())
                .overlay { Circle().strokeBorder(.white.opacity(0.25), lineWidth: 0.5) }
                .shadow(color: PaperTheme.accent.opacity(0.35), radius: 14, y: 6)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("AI 助手")
        .scaleEffect(fabHidden ? 0.5 : 1)
        .opacity(fabHidden ? 0 : 1)
        .allowsHitTesting(!fabHidden)
        .animation(PaperTheme.Motion.quick, value: fabHidden)
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
        .buttonStyle(.pressable)
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

    /// 空态：品牌标识 + 打开文件入口（轻微入场：fade + 上移）。
    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer()
            Image("BrandMark")
                .resizable()
                .scaledToFit()
                .frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: PaperTheme.Radius.xlarge, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: PaperTheme.Radius.xlarge, style: .continuous)
                        .strokeBorder(PaperTheme.hairline, lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.08), radius: 12, y: 4)

            HStack(alignment: .center, spacing: 10) {
                Text("MEditor")
                    .font(PaperTheme.Typography.brandTitle())
                    .foregroundStyle(PaperTheme.ink)
                // 印章「盖下」：放大淡入后弹落到名旁，像真章落纸
                SealStamp(size: 28)
                    .offset(y: 4)
                    .scaleEffect(sealStamped ? 1 : 1.8)
                    .opacity(sealStamped ? 1 : 0)
                    .rotationEffect(.degrees(sealStamped ? 0 : 12))
            }
            .padding(.top, 26)

            Text("纸墨之间，从容书写。")
                .font(PaperTheme.Typography.uiTitle3())
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
        .opacity(emptyStateVisible ? 1 : 0)
        .offset(y: emptyStateVisible ? 0 : 14)
        .onAppear {
            withAnimation(PaperTheme.Motion.gentle) { emptyStateVisible = true }
            // 印章晚半拍盖下，等名字先落纸
            withAnimation(.spring(response: 0.32, dampingFraction: 0.62).delay(0.4)) {
                sealStamped = true
            }
        }
    }
}
