import SwiftUI

/// Markdown 块级预览：把原文解析成标题 / 段落 / 列表 / 任务 / 代码块 / 引用 / 分割线，
/// 每块独立排版（系统 AttributedString 整体渲染会丢失块级结构，且无法做悬挂缩进与容器样式）。
struct MarkdownPreviewView: View {
    let source: String

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(Array(Self.parse(source).enumerated()), id: \.offset) { _, block in
                    blockView(block)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, PaperTheme.Spacing.page)
            .padding(.vertical, 20)
        }
        .onAppear { preloadMermaidIfNeeded() }
        .onChange(of: source) { preloadMermaidIfNeeded() }
    }

    /// 文档含 mermaid 块时：预热共享引擎，并把全部图表按文档顺序预渲染进缓存——
    /// JS 解析与首屏渲染并行，屏外的图表也不用等滚动到才开始渲染。
    private func preloadMermaidIfNeeded() {
        guard source.contains("```mermaid") else { return }
        let codes = Self.parse(source).compactMap { block -> String? in
            guard case .codeBlock(let language, let code) = block,
                  language?.lowercased() == "mermaid" else { return nil }
            return code
        }
        MermaidRenderer.shared.preload(codes: codes, scale: displayScale)
    }

    // MARK: - 块模型

    enum ListMarker {
        case bullet
        case ordered(Int)
        case task(checked: Bool)
    }

    enum Block {
        case heading(level: Int, text: String)
        case paragraph(text: String)
        case listItem(marker: ListMarker, indent: Int, text: String)
        case codeBlock(language: String?, code: String)
        case quote(text: String)
        case thematicBreak
    }

    // MARK: - 解析（按行扫描的轻量 block parser）

    static func parse(_ text: String) -> [Block] {
        var blocks: [Block] = []
        var paragraphLines: [String] = []
        var quoteLines: [String] = []
        var codeLines: [String]? = nil
        var codeLang: String? = nil

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            blocks.append(.paragraph(text: paragraphLines.joined(separator: " ")))
            paragraphLines = []
        }
        func flushQuote() {
            guard !quoteLines.isEmpty else { return }
            blocks.append(.quote(text: quoteLines.joined(separator: " ")))
            quoteLines = []
        }

        for rawLine in text.components(separatedBy: .newlines) {
            //  fenced code：开闭之间原样累计
            if rawLine.hasPrefix("```") {
                if codeLines != nil {
                    blocks.append(.codeBlock(language: codeLang, code: (codeLines ?? []).joined(separator: "\n")))
                    codeLines = nil; codeLang = nil
                } else {
                    flushParagraph(); flushQuote()
                    codeLines = []
                    let lang = rawLine.dropFirst(3).trimmingCharacters(in: .whitespaces)
                    codeLang = lang.isEmpty ? nil : lang
                }
                continue
            }
            if codeLines != nil { codeLines?.append(rawLine); continue }

            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { flushParagraph(); flushQuote(); continue }

            // 分割线：--- / *** / ___
            if line.allSatisfy({ $0 == "-" || $0 == "*" || $0 == "_" }), line.count >= 3,
               line.filter({ $0 == "-" }).count == line.count
                || line.filter({ $0 == "*" }).count == line.count
                || line.filter({ $0 == "_" }).count == line.count {
                flushParagraph(); flushQuote()
                blocks.append(.thematicBreak)
                continue
            }

            // 标题：# … ######
            if let match = line.firstMatch(of: /^(#{1,6})\s+(.*)$/) {
                flushParagraph(); flushQuote()
                blocks.append(.heading(level: match.1.count, text: String(match.2)))
                continue
            }

            // 引用：> …（连续行合并）
            if line.hasPrefix(">") {
                flushParagraph()
                quoteLines.append(String(line.dropFirst()).trimmingCharacters(in: .whitespaces))
                continue
            }
            flushQuote()

            // 列表：-/*/+ 、1. 、- [ ]/- [x]（按前导空格计算缩进层级）
            let indent = rawLine.prefix(while: { $0 == " " }).count / 2
            if let m = line.firstMatch(of: /^[-*+]\s+\[([ xX])\]\s+(.*)$/) {
                flushParagraph()
                blocks.append(.listItem(marker: .task(checked: m.1 != " "), indent: indent, text: String(m.2)))
                continue
            }
            if let m = line.firstMatch(of: /^[-*+]\s+(.*)$/) {
                flushParagraph()
                blocks.append(.listItem(marker: .bullet, indent: indent, text: String(m.1)))
                continue
            }
            if let m = line.firstMatch(of: /^(\d+)[.)]\s+(.*)$/) {
                flushParagraph()
                blocks.append(.listItem(marker: .ordered(Int(m.1) ?? 1), indent: indent, text: String(m.2)))
                continue
            }

            paragraphLines.append(line)
        }

        flushParagraph(); flushQuote()
        if let dangling = codeLines { // 未闭合的 fenced code 兜底
            blocks.append(.codeBlock(language: codeLang, code: dangling.joined(separator: "\n")))
        }
        return blocks
    }

    // MARK: - 渲染

    @ViewBuilder
    private func blockView(_ block: Block) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(inline(text))
                .font(Self.headingFont(level))
                .foregroundStyle(PaperTheme.ink)
                .lineSpacing(4)
                .padding(.top, level <= 2 ? 14 : 8)

        case .paragraph(let text):
            Text(inline(text))
                .font(.system(size: 17))
                .foregroundStyle(PaperTheme.ink)
                .lineSpacing(7)

        case .listItem(let marker, let indent, let text):
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                markerView(marker)
                    .frame(width: 16, alignment: .trailing)
                Text(inline(text, strikethrough: marker.isCheckedTask))
                    .font(.system(size: 17))
                    .foregroundStyle(marker.isCheckedTask ? PaperTheme.inkSecondary : PaperTheme.ink)
                    .lineSpacing(6)
            }
            .padding(.leading, CGFloat(indent) * 20 + 2)

        case .codeBlock(let language, let code):
            if language?.lowercased() == "mermaid" {
                MermaidBlockView(code: code)
            } else {
                codeBlockView(language: language, code: code)
            }

        case .quote(let text):
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(PaperTheme.accent.opacity(0.45))
                    .frame(width: 3)
                Text(inline(text))
                    .font(.system(size: 16.5))
                    .foregroundStyle(PaperTheme.inkSecondary)
                    .lineSpacing(7)
            }
            .padding(.leading, 2)

        case .thematicBreak:
            PaperTheme.hairline
                .frame(height: 0.5)
                .padding(.vertical, 6)
        }
    }

    /// 普通代码块：语言标签 + 横向滚动等宽文本。
    private func codeBlockView(language: String?, code: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let language {
                Text(language.lowercased())
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(PaperTheme.inkSecondary)
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(PaperTheme.Typography.code)
                    .foregroundStyle(PaperTheme.ink)
                    .lineSpacing(5)
                    .padding(.horizontal, 14)
                    .padding(.vertical, language == nil ? 14 : 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PaperTheme.codeBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// 列表标记：圆点 / 序号 / 任务勾选框。
    @ViewBuilder
    private func markerView(_ marker: ListMarker) -> some View {
        switch marker {
        case .bullet:
            Text("•")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(PaperTheme.accent.opacity(0.8))
        case .ordered(let n):
            Text("\(n).")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(PaperTheme.inkSecondary)
        case .task(let checked):
            Image(systemName: checked ? "checkmark.square.fill" : "square")
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(checked ? PaperTheme.accent : PaperTheme.inkSecondary.opacity(0.6))
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2 }
        }
    }

    private static func headingFont(_ level: Int) -> Font {
        switch level {
        case 1:  return .system(size: 30, weight: .bold, design: .serif)
        case 2:  return .system(size: 23, weight: .semibold, design: .serif)
        case 3:  return .system(size: 19, weight: .semibold, design: .serif)
        default: return .system(size: 17, weight: .semibold, design: .serif)
        }
    }

    /// 行内样式：系统解析 inline intent（粗体 / 斜体 / 删除线），
    /// 再补行内代码底色与链接色。
    private func inline(_ s: String, strikethrough: Bool = false) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        var a = (try? AttributedString(markdown: s, options: options)) ?? AttributedString(s)
        for run in a.runs {
            if run.inlinePresentationIntent?.contains(.code) == true {
                a[run.range].font = .system(size: 15, design: .monospaced)
                a[run.range].backgroundColor = PaperTheme.codeBackground
            }
            if run.link != nil {
                a[run.range].foregroundColor = PaperTheme.accent
            }
        }
        if strikethrough {
            a.strikethroughStyle = .single
        }
        return a
    }
}

private extension MarkdownPreviewView.ListMarker {
    var isCheckedTask: Bool {
        if case .task(let checked) = self { return checked }
        return false
    }
}
