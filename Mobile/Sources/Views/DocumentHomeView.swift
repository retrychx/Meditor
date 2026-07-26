import SwiftUI
import UniformTypeIdentifiers

/// 文件列表页（App 一级页面）：搜索 + 白卡列表——打开 / 置顶 / 重命名 / 删除。
/// 页面切换（文档/设置）与底部栏由 RootView 提供；AI 经 hero 浮层唤起。
struct DocumentHomeView: View {
    @Environment(DocumentStore.self) private var store

    /// 打开文档成功后的回调（RootView 推进文档页）。
    let onOpenDocument: () -> Void

    @State private var showingFilePicker = false
    /// 重命名目标（非 nil 时弹输入框）。
    @State private var renaming: DocumentStore.RecentDocument? = nil
    @State private var renameText = ""
    /// 操作失败的简单提示。
    @State private var actionError: String? = nil
    /// 列表搜索词。
    @State private var query = ""

    /// 与 DocumentView 保持一致的可导入类型。
    private static let importableTypes: [UTType] = [
        .plainText, .html,
        UTType(filenameExtension: "md"),
        UTType(filenameExtension: "markdown"),
    ].compactMap { $0 }

    var body: some View {
        Group {
            if store.recentDocuments.isEmpty {
                emptyState
            } else {
                documentList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PaperTheme.paper.ignoresSafeArea())
        .navigationTitle("文档")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // 与 DocumentView 一致的自绘衬线标题；页面切换与底栏在 RootView。
            ToolbarItem(placement: .principal) {
                Text("文档")
                    .font(.system(.headline, design: .serif, weight: .semibold))
                    .foregroundStyle(PaperTheme.ink)
            }
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: Self.importableTypes,
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                store.openIncoming(url)
                if store.lastError == nil { onOpenDocument() }
            }
        }
        .alert("重命名", isPresented: Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } }
        )) {
            TextField("文件名", text: $renameText)
            Button("取消", role: .cancel) { renaming = nil }
            Button("确定") { commitRename() }
        } message: {
            Text("保留原扩展名；与现有文件重名时自动追加数字后缀。")
        }
        .alert("提示", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("好", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
        .onAppear { store.refreshWorkspaceDocuments() }
    }

    // MARK: - 列表（Craft 式：搜索 + 白卡；滑动置顶/重命名/删除）

    private var filteredDocs: [DocumentStore.RecentDocument] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return store.recentDocuments }
        return store.recentDocuments.filter { $0.fileName.localizedCaseInsensitiveContains(q) }
    }

    /// 让 List 行呈现白卡外观的统一配置：透明行底、隐藏分隔、留边距。
    private func cardRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
    }

    private var documentList: some View {
        List {
            cardRow {
                searchField
            }
            cardRow {
                // 「打开文件」入口：保持在列表顶部，触手可及。
                Button { showingFilePicker = true } label: {
                    Label("打开文件…", systemImage: "folder")
                        .font(.body.weight(.medium))
                        .foregroundStyle(PaperTheme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(PaperTheme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(color: PaperTheme.cardShadow, radius: 8, y: 3)
                }
                .buttonStyle(.pressable)
            }
            ForEach(filteredDocs, id: \.relativePath) { doc in
                cardRow {
                    card(for: doc)
                }
                .swipeActions(edge: .leading) {
                    Button { store.togglePin(doc.relativePath) } label: {
                        Label(doc.pinned ? "取消置顶" : "置顶",
                              systemImage: doc.pinned ? "pin.slash" : "pin")
                    }
                    .tint(PaperTheme.accent)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { delete(doc) } label: {
                        Label("删除", systemImage: "trash")
                    }
                    Button { beginRename(doc) } label: {
                        Label("重命名", systemImage: "pencil")
                    }
                    .tint(PaperTheme.inkSecondary)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        // 底部悬浮栏不挡卡片：滚动内容底部留白
        .contentMargins(.bottom, 84, for: .scrollContent)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15))
                .foregroundStyle(PaperTheme.inkSecondary)
            TextField("搜索文档", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(PaperTheme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: PaperTheme.cardShadow, radius: 8, y: 3)
    }

    private func card(for doc: DocumentStore.RecentDocument) -> some View {
        Button { open(doc) } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        if doc.pinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(PaperTheme.accent)
                        }
                        Text(doc.fileName)
                            .font(.system(.headline, design: .serif, weight: .semibold))
                            .foregroundStyle(PaperTheme.ink)
                            .lineLimit(1)
                    }
                    Text(snippet(for: doc.relativePath))
                        .font(.subheadline)
                        .foregroundStyle(PaperTheme.inkSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 6) {
                    Text(doc.lastOpened.formatted(.relative(presentation: .named)))
                        .font(.caption)
                        .foregroundStyle(PaperTheme.inkSecondary)
                    Menu {
                        Button { beginRename(doc) } label: {
                            Label("重命名", systemImage: "pencil")
                        }
                        Button { store.togglePin(doc.relativePath) } label: {
                            Label(doc.pinned ? "取消置顶" : "置顶",
                                  systemImage: doc.pinned ? "pin.slash" : "pin")
                        }
                        Divider()
                        Button(role: .destructive) { delete(doc) } label: {
                            Label("删除", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(PaperTheme.inkSecondary)
                            .frame(width: 26, height: 26)
                            .contentShape(Rectangle())
                    }
                }
            }
            .padding(14)
            .background(PaperTheme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: PaperTheme.cardShadow, radius: 8, y: 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 空态

    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer()
            Image(systemName: "doc.text")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(PaperTheme.inkSecondary)
            Text("暂无文档")
                .font(PaperTheme.Typography.uiTitle3())
                .foregroundStyle(PaperTheme.ink)
                .padding(.top, 16)
            Text("从文件 App 选择 .md / .html 打开，或在微信等 App 中选择「用其他应用打开」发送到 MEditor。")
                .font(.subheadline)
                .foregroundStyle(PaperTheme.inkSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .frame(maxWidth: 300)
                .padding(.top, 12)
            Button { showingFilePicker = true } label: {
                Label("打开文件", systemImage: "folder")
            }
            .buttonStyle(.paperPrimary)
            .padding(.top, 24)
            Spacer()
        }
        .padding(.horizontal, PaperTheme.Spacing.page)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 操作

    private func open(_ doc: DocumentStore.RecentDocument) {
        let url = store.workspace.appendingPathComponent(doc.relativePath)
        if store.loadFromSandbox(url) {
            onOpenDocument()
        } else {
            // 文件可能已被外部删除：刷新列表清掉失效记录，并告知用户。
            store.refreshWorkspaceDocuments()
            actionError = "无法打开「\(doc.fileName)」，文件可能已被移除。"
        }
    }

    private func beginRename(_ doc: DocumentStore.RecentDocument) {
        renaming = doc
        renameText = (doc.fileName as NSString).deletingPathExtension
    }

    private func commitRename() {
        guard let doc = renaming else { return }
        if store.renameDocument(at: doc.relativePath, to: renameText) == nil {
            actionError = "重命名失败，请检查文件名是否有效。"
        }
        renaming = nil
    }

    private func delete(_ doc: DocumentStore.RecentDocument) {
        store.deleteDocument(at: doc.relativePath)
        // 删的是当前打开文档：store.sandboxURL 变 nil，RootView 会自动退回列表页。
    }

    /// 首行内容摘要：只读前 4KB，取第一个非空行并去掉 Markdown 标题/引用/列表标记。
    private func snippet(for rel: String) -> String {
        let url = store.workspace.appendingPathComponent(rel)
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 4096), !data.isEmpty else { return "" }
        // read(upToCount:) 可能截断在多字节字符中间，String(decoding:) 保证不失败。
        let raw = String(decoding: data, as: UTF8.self)
        let line = raw.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        return line.replacingOccurrences(of: "^[#>\\-*+\\s]+", with: "", options: .regularExpression)
    }
}
