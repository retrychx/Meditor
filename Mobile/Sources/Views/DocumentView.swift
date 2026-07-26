import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 文档视图：编辑（TextEditor）与预览（Markdown 原生渲染 / HTML WebView）切换。
struct DocumentView: View {
    @Environment(DocumentStore.self) private var store
    @Environment(ReaderSettings.self) private var reader

    @State private var showingFilePicker = false
    @State private var showingOpenError = false
    /// 发布在线链接的结果弹窗（成功=链接已复制 / 失败=错误信息）。
    @State private var publishAlert: (message: String, url: String?)? = nil
    /// 预览滚动越顶：导航栏从透明过渡到纸底 + 发丝分隔。
    @State private var contentScrolled = false
    /// 空态入场动画开关。
    @State private var emptyStateVisible = false
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(PaperTheme.Motion.standard, value: store.showPreview)
        // 底栏悬浮在内容之上（safearea 透底），不占布局高度
        .overlay(alignment: .bottom) { actionBar }
        .background(PaperTheme.paper.ignoresSafeArea())
        .navigationTitle(store.hasDocument ? store.fileName : "MEditor")
        .navigationBarTitleDisplayMode(.inline)
        // 透明 ↔ 纸底的过渡随滚动状态缓动
        .toolbarBackground(transparentHeader ? .hidden : .visible, for: .navigationBar)
        .animation(PaperTheme.Motion.gentle, value: transparentHeader)
        .onPreferenceChange(PreviewScrollOffsetKey.self) { minY in
            contentScrolled = minY < -8
        }
        .toolbar {
            // 标题自绘：文档文件名 / 品牌字保留衬线（UI chrome 其余部分是无衬线）。
            // 操作动作全部沉到底部动作条，头部只留标题和 ⋯ 菜单。
            ToolbarItem(placement: .principal) {
                Text(store.hasDocument ? store.fileName : "MEditor")
                    .font(.system(.headline, design: .serif, weight: .semibold))
                    .foregroundStyle(PaperTheme.ink)
                    .lineLimit(1)
            }
            if store.hasDocument {
                ToolbarItem(placement: .topBarTrailing) {
                    documentMenu
                }
            }
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
        // 打开失败：无论空态还是已有文档，都明确弹窗告知（真机权限/iCloud 问题全靠它暴露）
        .onChange(of: store.lastError) { _, newValue in
            showingOpenError = newValue != nil
        }
        .alert("无法打开文件", isPresented: $showingOpenError) {
            Button("好", role: .cancel) { store.lastError = nil }
        } message: {
            Text(store.lastError ?? "")
        }
        // 发布结果：成功显示链接已复制（可打开），失败显示原因
        .alert("在线分享", isPresented: Binding(
            get: { publishAlert != nil },
            set: { if !$0 { publishAlert = nil } }
        )) {
            if let url = publishAlert?.url, let link = URL(string: url) {
                Button("打开链接") { UIApplication.shared.open(link) }
            }
            Button("好", role: .cancel) { publishAlert = nil }
        } message: {
            Text(publishAlert?.message ?? "")
        }
    }

    // MARK: - 底部栏（与一级页面同一语言：双胶囊白底玻璃态）

    /// 胶囊底：与一级页面共用同一玻璃质感（GlassCapsuleBackground）。
    private var capsuleBackground: some View {
        GlassCapsuleBackground()
    }

    private var actionBar: some View {
        HStack(spacing: 0) {
            // 编辑/预览胶囊
            HStack(spacing: 4) {
                modeButton
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(capsuleBackground)

            Spacer()

            // 动作胶囊：墨（AI）/ ＋（新建）
            HStack(spacing: 8) {
                BarAIButton(context: "doc")
                BarPlusButton(context: "doc")
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(capsuleBackground)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 4)
        // 键盘弹出时动作条保持贴底（被键盘遮住），不被顶上去
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    /// 编辑/预览切换：预览态铅笔（点去编辑）、编辑态文档高亮（点回预览），morph 过渡。
    private var modeButton: some View {
        Button { store.showPreview.toggle() } label: {
            Image(systemName: store.showPreview ? "pencil" : "doc.richtext")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(store.showPreview ? PaperTheme.inkSecondary : PaperTheme.accent)
                .contentTransition(.symbolEffect(.replace.downUp))
                .frame(width: 52)
                .padding(.vertical, 8)
                .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(store.showPreview ? "编辑" : "预览")
    }

    /// 导航栏「⋯」菜单：阅读设置 / 分享 / 复制等文档级操作的归宿。
    private var documentMenu: some View {
        Menu {
            Menu {
                Section("字号") {
                    ForEach(ReaderSettings.FontScale.allCases) { scale in
                        Button {
                            reader.fontScale = scale
                        } label: {
                            if reader.fontScale == scale {
                                Label(scale.displayName, systemImage: "checkmark")
                            } else {
                                Text(scale.displayName)
                            }
                        }
                    }
                }
                Section("行距") {
                    ForEach(ReaderSettings.LineSpacing.allCases) { spacing in
                        Button {
                            reader.lineSpacing = spacing
                        } label: {
                            if reader.lineSpacing == spacing {
                                Label(spacing.displayName, systemImage: "checkmark")
                            } else {
                                Text(spacing.displayName)
                            }
                        }
                    }
                }
            } label: {
                Label("阅读设置", systemImage: "textformat.size")
            }
            ShareLink(item: store.text, subject: Text(store.fileName)) {
                Label("分享全文", systemImage: "square.and.arrow.up")
            }
            if store.kind == .markdown {
                Button {
                    publishOnline()
                } label: {
                    if ShareLinkPublisher.shared.isPublishing {
                        Label("正在发布…", systemImage: "globe")
                    } else {
                        Label("发布在线链接", systemImage: "globe")
                    }
                }
                .disabled(ShareLinkPublisher.shared.isPublishing)
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

    /// 发布当前 Markdown 文档为在线链接；结果经弹窗反馈。
    private func publishOnline() {
        let publisher = ShareLinkPublisher.shared
        publisher.refreshTokenStatus()
        guard publisher.isConfigured else {
            publishAlert = (message: "请先在 设置 → 在线分享 中配置 Token", url: nil)
            return
        }
        Task {
            await publisher.publish(fileName: store.fileName, markdown: store.text)
            if let url = publisher.lastResultURL {
                publishAlert = (message: "链接已复制到剪贴板：\n\(url)", url: url)
            } else {
                publishAlert = (message: publisher.lastError ?? "发布失败", url: nil)
            }
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
            // UITextView 封装：拿得到光标，挂 Markdown 键盘工具条。
            MarkdownTextEditor(text: Binding(
                get: { store.text },
                set: { store.applyManualEdit($0) }
            ), fontScale: reader.scaleFactor)
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
                .shadow(color: PaperTheme.cardShadow, radius: 12, y: 4)

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
