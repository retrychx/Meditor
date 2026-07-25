import SwiftUI
import UniformTypeIdentifiers

/// 最近文档首页（sheet）：纸墨风格的文档列表——打开 / 置顶 / 重命名 / 删除，
/// 顶部保留「打开文件」入口（系统文件选择器），空态给出引导。
struct DocumentHomeView: View {
    @Environment(DocumentStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var showingFilePicker = false
    /// 重命名目标（非 nil 时弹输入框）。
    @State private var renaming: DocumentStore.RecentDocument? = nil
    @State private var renameText = ""
    /// 操作失败的简单提示。
    @State private var actionError: String? = nil

    /// 与 DocumentView 保持一致的可导入类型。
    private static let importableTypes: [UTType] = [
        .plainText, .html,
        UTType(filenameExtension: "md"),
        UTType(filenameExtension: "markdown"),
    ].compactMap { $0 }

    var body: some View {
        NavigationStack {
            Group {
                if store.recentDocuments.isEmpty {
                    emptyState
                } else {
                    documentList
                }
            }
            .background(PaperTheme.paper.ignoresSafeArea())
            .navigationTitle("文档")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // 与 DocumentView 一致的自绘衬线标题。
                ToolbarItem(placement: .principal) {
                    Text("文档")
                        .font(.system(.headline, design: .serif, weight: .semibold))
                        .foregroundStyle(PaperTheme.ink)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15))
                            .foregroundStyle(PaperTheme.inkSecondary)
                    }
                    .buttonStyle(.pressable)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingFilePicker = true } label: {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 15))
                            .foregroundStyle(PaperTheme.inkSecondary)
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel("打开文件")
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
                dismiss()
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

    // MARK: - 列表

    private var documentList: some View {
        List {
            // 「打开文件」入口行：保持在列表顶部，触手可及。
            Button { showingFilePicker = true } label: {
                Label("打开文件…", systemImage: "folder")
                    .font(.body.weight(.medium))
                    .foregroundStyle(PaperTheme.accent)
            }
            .listRowBackground(PaperTheme.card)

            ForEach(store.recentDocuments, id: \.relativePath) { doc in
                row(for: doc)
                    .listRowBackground(PaperTheme.card)
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
                    .contextMenu {
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
                    }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func row(for doc: DocumentStore.RecentDocument) -> some View {
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
                Text(doc.lastOpened.formatted(.relative(presentation: .named)))
                    .font(.caption)
                    .foregroundStyle(PaperTheme.inkSecondary)
            }
            .padding(.vertical, 4)
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
            dismiss()
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
        let url = store.workspace.appendingPathComponent(doc.relativePath)
        let wasCurrent = store.sandboxURL?.standardizedFileURL == url.standardizedFileURL
        store.deleteDocument(at: doc.relativePath)
        // 删的是当前打开文档：关掉首页，回到无文档空态。
        if wasCurrent { dismiss() }
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
