import SwiftUI

/// Template picker — Craft-inspired: a search header, sectioned scroll, and
/// rich cards that each render a miniature preview of the template's layout.
struct TemplatePickerSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    let store: TemplateStoreProtocol
    let onSelect: (DocumentTemplate) -> Void

    @State private var query = ""
    @State private var selectedID: String? = "blank"
    @FocusState private var searchFocused: Bool

    private let columns = [GridItem(.adaptive(minimum: 132, maximum: 168), spacing: 16)]

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.6)
            content
            Divider().opacity(0.6)
            footer
        }
        .frame(width: 580, height: 480)
        .background(DS.Color.editorBg)
        .onAppear { searchFocused = true }
    }

    // MARK: - Header (search)

    private var header: some View {
        HStack(spacing: DS.Space.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 13, weight: .medium))
            TextField(L("template.search"), text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5))
                .focused($searchFocused)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, DS.Space.md)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .padding(.horizontal, DS.Space.lg)
        .padding(.vertical, DS.Space.md)
        .animation(DS.Motion.fast, value: query.isEmpty)
    }

    // MARK: - Content

    private var content: some View {
        Group {
            if sections.allSatisfy({ $0.items.isEmpty }) {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Space.lg) {
                        ForEach(sections) { section in
                            if !section.items.isEmpty {
                                sectionView(section)
                            }
                        }
                    }
                    .padding(DS.Space.lg)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sectionView(_ section: Section) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Text(section.title.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.tertiary)
                .kerning(0.5)

            LazyVGrid(columns: columns, spacing: DS.Space.lg) {
                ForEach(section.items) { template in
                    TemplateCard(
                        template: template,
                        isSelected: selectedID == template.id,
                        onDelete: template.isBuiltin ? nil : { try? store.delete(id: template.id) }
                    )
                    .onTapGesture {
                        withAnimation(DS.Motion.springFast) { selectedID = template.id }
                    }
                    .onTapGesture(count: 2) {
                        selectedID = template.id
                        confirmSelection()
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: DS.Space.sm) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.tertiary)
            Text(L("common.noMatches"))
                .font(.system(size: 12.5))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if let id = selectedID, let template = store.template(byID: id) {
                HStack(spacing: 7) {
                    TemplateThumbnail(kind: .init(template), accent: TemplateKind(template).accent)
                        .frame(width: 22, height: 16)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.primary.opacity(0.1)))
                    Text(template.name)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(L("template.selectHint"))
                    .font(.system(size: 12.5))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button(L("common.cancel")) { dismiss() }
                .keyboardShortcut(.escape, modifiers: [])
            Button(L("template.create")) { confirmSelection() }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
                .tint(Color.appAccent)
                .disabled(selectedID == nil)
        }
        .padding(.horizontal, DS.Space.lg)
        .padding(.vertical, DS.Space.md)
    }

    // MARK: - Sections data

    private struct Section: Identifiable {
        let id: String
        let title: String
        let items: [DocumentTemplate]
    }

    private var sections: [Section] {
        if !query.isEmpty {
            return [Section(id: "search", title: L("template.search"), items: allFiltered)]
        }
        let mine = store.allTemplates().filter { !$0.isBuiltin }
        var result = [Section(id: "builtin", title: "内置模板", items: store.builtinTemplates())]
        if !mine.isEmpty { result.append(Section(id: "mine", title: "我的模板", items: mine)) }
        return result
    }

    private var allFiltered: [DocumentTemplate] {
        let q = query.lowercased()
        return store.allTemplates().filter {
            $0.name.lowercased().contains(q) || $0.description.lowercased().contains(q)
        }
    }

    private func confirmSelection() {
        guard let id = selectedID, let template = store.template(byID: id) else { return }
        onSelect(template)
        dismiss()
    }
}

// MARK: - Template Kind (drives thumbnail layout + accent)

enum TemplateKind {
    case blank, meeting, tech, weekly, journal, html, generic

    init(_ t: DocumentTemplate) {
        let n = t.name.lowercased(), id = t.id.lowercased()
        if id == "blank" || n.contains("空白") || n.contains("blank") { self = .blank }
        else if id.contains("meeting") || n.contains("会议") { self = .meeting }
        else if id.contains("tech") || n.contains("技术") { self = .tech }
        else if id.contains("weekly") || n.contains("周报") { self = .weekly }
        else if id.contains("journal") || n.contains("日记") || n.contains("日报") { self = .journal }
        else if id.contains("html") || n.contains("html") { self = .html }
        else { self = .generic }
    }

    var accent: Color {
        switch self {
        case .blank:   return .gray
        case .meeting: return .blue
        case .tech:    return .purple
        case .weekly:  return .green
        case .journal: return .orange
        case .html:    return .teal
        case .generic: return .accentColor
        }
    }
}

// MARK: - Template Card

private struct TemplateCard: View {
    let template: DocumentTemplate
    let isSelected: Bool
    var onDelete: (() -> Void)? = nil

    @State private var isHovered = false

    private var kind: TemplateKind { TemplateKind(template) }

    var body: some View {
        VStack(spacing: DS.Space.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .fill(DS.Color.editorBg)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                            .stroke(isSelected ? kind.accent.opacity(0.9) : Color.primary.opacity(0.08),
                                    lineWidth: isSelected ? 2 : 1)
                    )
                    .shadow(color: .black.opacity(isHovered || isSelected ? 0.14 : 0.06),
                            radius: isHovered || isSelected ? 9 : 4,
                            y: isHovered || isSelected ? 4 : 2)

                TemplateThumbnail(kind: kind, accent: kind.accent)
                    .padding(12)
            }
            .frame(height: 96)
            .scaleEffect(isHovered && !isSelected ? 1.02 : 1)

            Text(template.name)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.78))
                .lineLimit(1)
        }
        .overlay(alignment: .topTrailing) {
            if isHovered, let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .background(Circle().fill(DS.Color.editorBg))
                }
                .buttonStyle(.plain)
                .offset(x: 6, y: -6)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .contentShape(Rectangle())
        .animation(DS.Motion.fast, value: isSelected)
        .animation(DS.Motion.micro, value: isHovered)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Template Thumbnail (miniature document preview)

private struct TemplateThumbnail: View {
    let kind: TemplateKind
    let accent: Color

    private var faint: Color { Color.primary.opacity(0.14) }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            switch kind {
            case .blank:
                bar(accent, 26)
                Spacer(minLength: 0)
                bar(faint, 40)
            case .meeting:
                bar(accent, 48)
                checkRow(34); checkRow(28)
                miniTable()
            case .tech:
                bar(accent, 46)
                bar(faint, 30, h: 4)
                line(58); line(48)
                miniTable()
            case .weekly:
                bar(accent, 42)
                bulletRow(46); bulletRow(52); bulletRow(38)
            case .journal:
                bar(accent, 36)
                line(56); line(44)
                bar(faint, 26, h: 4)
            case .html:
                codeMark()
                line(50); line(40)
            case .generic:
                bar(accent, 40)
                line(56); line(48); line(36)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: building blocks

    private func bar(_ c: Color, _ w: CGFloat, h: CGFloat = 6) -> some View {
        RoundedRectangle(cornerRadius: h / 2, style: .continuous).fill(c).frame(width: w, height: h)
    }
    private func line(_ w: CGFloat) -> some View { bar(faint, w, h: 4) }

    private func checkRow(_ w: CGFloat) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .stroke(faint, lineWidth: 1).frame(width: 6, height: 6)
            bar(faint, w, h: 4)
        }
    }
    private func bulletRow(_ w: CGFloat) -> some View {
        HStack(spacing: 5) {
            Circle().fill(accent.opacity(0.5)).frame(width: 4, height: 4)
            bar(faint, w, h: 4)
        }
    }
    private func miniTable() -> some View {
        VStack(spacing: 0) {
            ForEach(0..<2, id: \.self) { _ in
                HStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { _ in
                        Rectangle().stroke(faint, lineWidth: 0.8)
                            .frame(width: 18, height: 9)
                    }
                }
            }
        }
        .padding(.top, 2)
    }
    private func codeMark() -> some View {
        HStack(spacing: 3) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(accent)
        }
    }
}
