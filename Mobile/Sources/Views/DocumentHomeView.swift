import SwiftUI
import UniformTypeIdentifiers

/// 文件列表页（App 一级页面）：搜索 + 白卡列表——打开 / 置顶 / 重命名 / 删除。
/// 页面切换（文档/设置）与底部栏由 RootView 提供；AI 经 hero 浮层唤起。
struct DocumentHomeView: View {
    @Environment(DocumentStore.self) private var store
    @Environment(RecentHistory.self) private var recents

    /// 打开文档成功后的回调（RootView 推进文档页）。
    let onOpenDocument: () -> Void

    @State private var showingFilePicker = false
    /// 重命名目标（非 nil 时弹输入框）。
    @State private var renaming: RecentHistory.RecentDocument? = nil
    @State private var renameText = ""
    /// 操作失败的简单提示。
    @State private var actionError: String? = nil
    /// 待确认删除的目标（非 nil 时弹确认对话框）。
    @State private var confirmDelete: RecentHistory.RecentDocument? = nil
    /// 列表搜索词。
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    /// 与 DocumentView 保持一致的可导入类型。
    private static let importableTypes: [UTType] = [
        .plainText, .html,
        UTType(filenameExtension: "md"),
        UTType(filenameExtension: "markdown"),
    ].compactMap { $0 }

    var body: some View {
        VStack(spacing: 0) {
            // 搜索框始终可见，无论是否有文档
            searchField
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

            if recents.documents.isEmpty {
                emptyState
            } else {
                documentList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PaperTheme.paperBackground)
        .navigationTitle("文档")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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
        .confirmationDialog(
            "确定删除此文档？",
            isPresented: Binding(
                get: { confirmDelete != nil },
                set: { if !$0 { confirmDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) { if let doc = confirmDelete { delete(doc) } }
            Button("取消", role: .cancel) { confirmDelete = nil }
        } message: {
            Text(confirmDelete.map { "「\($0.fileName)」将被永久删除。" } ?? "")
        }
        .onAppear { recents.refreshWorkspaceDocuments() }
    }

    // MARK: - 列表（Craft 式：搜索 + 白卡；滑动置顶/重命名/删除）

    private var filteredDocs: [RecentHistory.RecentDocument] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return recents.documents }
        return recents.documents.filter { $0.fileName.localizedCaseInsensitiveContains(q) }
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
            ForEach(filteredDocs, id: \.relativePath) { doc in
                cardRow {
                    card(for: doc)
                }
                .swipeActions(edge: .leading) {
                    Button { recents.togglePin(doc.relativePath) } label: {
                        Label(doc.pinned ? "取消置顶" : "置顶",
                              systemImage: doc.pinned ? "pin.slash" : "pin")
                    }
                    .tint(PaperTheme.accent)
                }
                .swipeActions(edge: .trailing) {
                    // 沙盒外文档（iCloud Drive 等）不支持在 App 内删除/重命名
                    if !doc.isExternal {
                        Button(role: .destructive) { confirmDelete = doc } label: {
                            Label("删除", systemImage: "trash")
                        }
                        Button { beginRename(doc) } label: {
                            Label("重命名", systemImage: "pencil")
                        }
                        .tint(PaperTheme.inkSecondary)
                    }
                }
            }
            // 搜索无结果
            if !query.isEmpty && filteredDocs.isEmpty {
                cardRow {
                    VStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 20))
                            .foregroundStyle(PaperTheme.inkSecondary)
                        Text("没有找到匹配的文档")
                            .font(.subheadline)
                            .foregroundStyle(PaperTheme.inkSecondary)
                        Text("试试换个关键词")
                            .font(.caption)
                            .foregroundStyle(PaperTheme.inkSecondary.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { recents.refreshWorkspaceDocuments() }
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
                .focused($searchFocused)
                .submitLabel(.search)
                .onSubmit { searchFocused = false }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(PaperTheme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: PaperTheme.cardShadow, radius: 8, y: 3)
    }

    /// 当前文档是否正在打开。沙盒外文档的 relativePath 是完整路径，直接比对。
    private func isCurrentDoc(_ doc: RecentHistory.RecentDocument) -> Bool {
        guard let url = store.sandboxURL else { return false }
        if doc.isExternal {
            return url.standardizedFileURL.path == doc.relativePath
        }
        let rel = (url.path.hasPrefix(recents.workspace.path + "/")
                   ? String(url.path.dropFirst(recents.workspace.path.count + 1))
                   : url.lastPathComponent)
        return rel == doc.relativePath
    }

    /// 从文件名提取扩展名（如 "md" / "html"）。
    private func fileExtension(_ name: String) -> String? {
        let ext = (name as NSString).pathExtension.lowercased()
        return ext.isEmpty || ext == name ? nil : ext
    }

    private func card(for doc: RecentHistory.RecentDocument) -> some View {
        Button { open(doc) } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        if doc.pinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(PaperTheme.accent)
                        }
                        Text(doc.baseName)
                            .font(.system(.headline, design: .serif, weight: .semibold))
                            .foregroundStyle(PaperTheme.ink)
                            .lineLimit(1)
                        if let ext = fileExtension(doc.fileName) {
                            Text(ext)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(PaperTheme.accent)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(PaperTheme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                        }
                        // 沙盒外原地打开的文档（iCloud Drive 等）标注云朵
                        if doc.isExternal {
                            Image(systemName: "icloud")
                                .font(.system(size: 11))
                                .foregroundStyle(PaperTheme.inkSecondary)
                        }
                    }
                    Text(doc.snippet)
                        .font(.subheadline)
                        .foregroundStyle(PaperTheme.inkSecondary)
                        .lineLimit(3)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 6) {
                    Text(dateLabel(doc.lastOpened))
                        .font(.caption)
                        .foregroundStyle(PaperTheme.inkSecondary)
                    Menu {
                        // 沙盒外文档（iCloud Drive 等）不支持在 App 内重命名/删除
                        if !doc.isExternal {
                            Button { beginRename(doc) } label: {
                                Label("重命名", systemImage: "pencil")
                            }
                        }
                        Button { recents.togglePin(doc.relativePath) } label: {
                            Label(doc.pinned ? "取消置顶" : "置顶",
                                  systemImage: doc.pinned ? "pin.slash" : "pin")
                        }
                        if !doc.isExternal {
                            Divider()
                            Button(role: .destructive) { delete(doc) } label: {
                                Label("删除", systemImage: "trash")
                            }
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
            .overlay(alignment: .leading) {
                if isCurrentDoc(doc) {
                    Rectangle()
                        .fill(PaperTheme.accent)
                        .frame(width: 3, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                        .padding(.leading, -1)
                }
            }
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
            HStack(spacing: 16) {
                Button { showingFilePicker = true } label: {
                    Label("打开文件", systemImage: "folder")
                }
                Button {
                    store.createDocument()
                    onOpenDocument()
                } label: {
                    Label("新建文档", systemImage: "plus")
                }
                .buttonStyle(.paperPrimary)
            }
            .padding(.top, 24)
            Spacer()
        }
        .padding(.horizontal, PaperTheme.Spacing.page)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 操作

    private func open(_ doc: RecentHistory.RecentDocument) {
        // 延迟到下一 runloop，让按钮按压动画和触感先完成，再同步读文件 + 导航
        Task { @MainActor in
            guard store.openRecent(doc) else {
                recents.refreshWorkspaceDocuments()
                actionError = store.lastError ?? "无法打开「\(doc.fileName)」，文件可能已被移除。"
                return
            }
            onOpenDocument()
        }
    }

    private func beginRename(_ doc: RecentHistory.RecentDocument) {
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

    private func delete(_ doc: RecentHistory.RecentDocument) {
        store.deleteDocument(at: doc.relativePath)
        // 删的是当前打开文档：store.sandboxURL 变 nil，RootView 会自动退回列表页。
    }

    /// 日期标签：今天→"今天"，昨天→"昨天"，更早→"M月d日"（跨年带年份）。
    /// iOS 内部对 FormatStyle 有缓存，但 static 复用更明确避免重复构造。
    private static let thisYearStyle = Date.FormatStyle().month(.abbreviated).day()
    private static let otherYearStyle = Date.FormatStyle().year().month(.abbreviated).day()

    private func dateLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "今天" }
        if cal.isDateInYesterday(date) { return "昨天" }
        if cal.isDate(date, equalTo: .now, toGranularity: .year) {
            return date.formatted(Self.thisYearStyle)
        }
        return date.formatted(Self.otherYearStyle)
    }
}
