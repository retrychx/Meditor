import SwiftUI
import WebKit

// MARK: - BeautifySheet

struct BeautifySheet: View {
    @Environment(AppState.self) private var state
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var htmlTemplates: [DocumentTemplate] = []
    @State private var selectedTemplate: DocumentTemplate? = nil
    @State private var generatedHTML: String = ""
    @State private var isGenerating = false
    @State private var htmlRevision = 0
    @State private var errorMessage: String? = nil
    @State private var showDiffSheet = false
    @State private var savedToastVisible = false
    @State private var streamTask: Task<Void, Never>? = nil

    @State private var tokenOverrides: [String: String] = [:]
    @State private var showCustomize: Bool = false

    private let agent = BeautifyAgent()

    private var targetHTMLURL: URL? {
        guard let url = state.selectedTab?.url else { return nil }
        let stem = url.deletingPathExtension()
        return stem.appendingPathExtension("html")
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            themeSelector
            customizeSection
            Divider()
            contentArea
            Divider()
            bottomBar
        }
        .frame(minWidth: 560, minHeight: 460)
        .sheet(isPresented: $showDiffSheet) {
            if let htmlURL = targetHTMLURL {
                BeautifyDiffSheet(
                    newHTML: generatedHTML,
                    existingURL: htmlURL,
                    onConfirm: {
                        saveHTML(to: htmlURL, overwrite: true)
                        showDiffSheet = false
                    },
                    onCancel: { showDiffSheet = false }
                )
            }
        }
        .overlay(alignment: .top) {
            if savedToastVisible {
                savedToast
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: savedToastVisible)
        .onAppear {
            let store = TemplateStore()
            htmlTemplates = store.htmlThemeTemplates()
            selectedTemplate = htmlTemplates.first(where: { $0.id == "html-craft" }) ?? htmlTemplates.first
            loadTokenOverrides()
        }
        .onChange(of: selectedTemplate?.id) { _, _ in loadTokenOverrides() }
        .onDisappear { streamTask?.cancel() }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.purple)
            Text("HTML 美化")
                .font(.system(size: 15, weight: .semibold))
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .background(Circle().fill(.quaternary))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: Theme selector

    private var themeSelector: some View {
        HStack(spacing: 10) {
            ForEach(htmlTemplates) { template in
                ThemeCard(template: template, isSelected: selectedTemplate?.id == template.id) {
                    selectedTemplate = template
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: Customize section

    private var customizeSection: some View {
        VStack(spacing: 0) {
            Divider()
            DisclosureGroup(isExpanded: $showCustomize) {
                VStack(spacing: 0) {
                    tokenColorRow(label: "强调色", key: "accent")
                    Divider().padding(.leading, 16)
                    tokenColorRow(label: "背景色", key: "bg")
                    Divider().padding(.leading, 16)
                    tokenColorRow(label: "文字色", key: "text")
                    Divider().padding(.leading, 16)
                    tokenTextRow(label: "字体", key: "font")
                    Divider().padding(.leading, 16)
                    tokenTextRow(label: "内容宽度", key: "width")
                    Divider().padding(.leading, 16)
                    tokenTextRow(label: "代码字体", key: "font-mono")
                    Divider().padding(.leading, 16)

                    HStack {
                        Spacer()
                        Button("恢复默认") { resetTokens() }
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
            } label: {
                HStack {
                    Text("自定义样式")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    if !tokenOverrides.isEmpty {
                        Text("\(tokenOverrides.count) 项已修改")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private func tokenColorRow(label: String, key: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .frame(width: 60, alignment: .leading)
            ColorPicker("", selection: colorBinding(key: key, defaultVal: defaultTokenValue(key)))
                .labelsHidden()
                .frame(width: 44)
            if let overrideVal = tokenOverrides[key] {
                Text(overrideVal)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            } else {
                Text(defaultTokenValue(key))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func tokenTextRow(label: String, key: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .frame(width: 60, alignment: .leading)
            TextField(defaultTokenValue(key), text: textBinding(key: key, defaultVal: defaultTokenValue(key)))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: Content area

    @ViewBuilder
    private var contentArea: some View {
        if isGenerating && generatedHTML.isEmpty {
            VStack(spacing: 14) {
                ProgressView()
                    .scaleEffect(0.9)
                Text("正在生成 HTML…")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if generatedHTML.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 32))
                    .foregroundStyle(.purple.opacity(0.4))
                Text("选择主题后点击「生成」")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ZStack(alignment: .topTrailing) {
                HTMLStringWebView(html: generatedHTML, revision: htmlRevision)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if isGenerating {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.7)
                        Text("生成中…")
                            .font(.system(size: 11))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.regularMaterial, in: Capsule())
                    .padding(10)
                }
            }
        }
    }

    private var generateButtonLabel: String {
        if isGenerating { return "停止" }
        return generatedHTML.isEmpty ? "生成" : "重新生成"
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 10) {
            if let err = errorMessage {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(err)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button("取消") { dismiss() }
                .keyboardShortcut(.escape, modifiers: [])

            Button(generateButtonLabel) {
                if isGenerating { stopGeneration() } else { startGeneration() }
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .buttonStyle(.borderedProminent)

            if !generatedHTML.isEmpty && !isGenerating {
                Button("保存 HTML") { handleSave() }
                    .keyboardShortcut("s", modifiers: [.command])
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: Toast

    private var savedToast: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            if let url = targetHTMLURL {
                Text("已保存 \(url.lastPathComponent)")
            } else {
                Text("已保存")
            }
        }
        .font(.system(size: 12.5, weight: .medium))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
    }

    // MARK: Actions

    private func startGeneration() {
        guard let tab = state.selectedTab, !tab.content.isEmpty,
              let template = selectedTemplate else { return }
        errorMessage = nil
        isGenerating = true
        generatedHTML = ""
        htmlRevision  = 0
        let markdown  = tab.content
        let overrides = tokenOverrides
        let s         = settings

        streamTask = agent.generate(
            markdown: markdown,
            template: template,
            tokenOverrides: overrides,
            settings: s,
            pluginManager: state.pluginManager,
            onChunk: { [self] chunk in
                generatedHTML += chunk
                htmlRevision  += 1
            },
            onComplete: { [self] _, error in
                isGenerating = false
                if let error {
                    errorMessage = (error as? AIError)?.errorDescription ?? error.localizedDescription
                }
            }
        )
    }

    private func stopGeneration() {
        streamTask?.cancel()
        streamTask  = nil
        isGenerating = false
    }

    private func handleSave() {
        guard let url = targetHTMLURL else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            showDiffSheet = true
        } else {
            saveHTML(to: url, overwrite: false)
        }
    }

    private func saveHTML(to url: URL, overwrite: Bool) {
        do {
            try generatedHTML.write(to: url, atomically: true, encoding: .utf8)
            withAnimation { savedToastVisible = true }
            Task {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                withAnimation { savedToastVisible = false }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Token helpers

    private func loadTokenOverrides() {
        guard let template = selectedTemplate else { return }
        var overrides: [String: String] = [:]
        for key in ["accent", "bg", "text", "font", "width", "font-mono"] {
            if let val = settings.themeToken(key, forTheme: template.id) {
                overrides[key] = val
            }
        }
        tokenOverrides = overrides
    }

    private func resetTokens() {
        guard let template = selectedTemplate else { return }
        for key in ["accent", "bg", "text", "font", "width", "font-mono"] {
            settings.setThemeToken(nil, token: key, forTheme: template.id)
        }
        tokenOverrides = [:]
    }

    private func defaultTokenValue(_ key: String) -> String {
        let d = BuiltinTemplates.tokenDefaults(for: selectedTemplate?.id ?? "")
        switch key {
        case "accent":    return d.accent
        case "bg":        return d.bg
        case "text":      return d.text
        case "font":      return d.font
        case "width":     return d.width
        case "font-mono": return d.fontMono
        default:          return ""
        }
    }

    private func colorBinding(key: String, defaultVal: String) -> Binding<Color> {
        Binding(
            get: { Color(hex: tokenOverrides[key] ?? defaultVal) },
            set: { color in
                let hex = color.hexString()
                tokenOverrides[key] = hex
                settings.setThemeToken(hex, token: key, forTheme: selectedTemplate?.id ?? "")
            }
        )
    }

    private func textBinding(key: String, defaultVal: String) -> Binding<String> {
        Binding(
            get: { tokenOverrides[key] ?? "" },
            set: { val in
                if val.isEmpty {
                    tokenOverrides.removeValue(forKey: key)
                    settings.setThemeToken(nil, token: key, forTheme: selectedTemplate?.id ?? "")
                } else {
                    tokenOverrides[key] = val
                    settings.setThemeToken(val, token: key, forTheme: selectedTemplate?.id ?? "")
                }
            }
        )
    }
}

// MARK: - Theme Card

private struct ThemeCard: View {
    let template: DocumentTemplate
    let isSelected: Bool
    let action: () -> Void

    private var icon: String {
        switch template.id {
        case "html-tufte": return "book.closed"
        case "html-craft": return "rectangle.stack"
        case "html-dark":  return "moon.stars"
        default:           return "doc.text"
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? .white : .primary)
                Text(template.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : .primary)
                Text(template.description)
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.purple : Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? Color.clear : Color.primary.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - HTMLStringWebView

/// Minimal WKWebView wrapper that loads HTML from a string.
struct HTMLStringWebView: NSViewRepresentable {
    let html: String
    let revision: Int

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.webView = webView
        webView.loadHTMLString(html, baseURL: nil)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard revision != context.coordinator.lastRevision else { return }
        context.coordinator.lastRevision = revision
        webView.loadHTMLString(html, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        weak var webView: WKWebView?
        var lastRevision = -1
    }
}
