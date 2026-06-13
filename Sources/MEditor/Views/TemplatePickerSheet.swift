import SwiftUI

/// Template picker — left category sidebar + right template grid.
struct TemplatePickerSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    let store: TemplateStoreProtocol
    let onSelect: (DocumentTemplate) -> Void

    @State private var query       = ""
    @State private var selectedID: String? = "blank"
    @State private var category    = TemplateCategory.builtin
    @FocusState private var searchFocused: Bool

    enum TemplateCategory: String, CaseIterable {
        case builtin = "内置模板"
        case mine    = "我的模板"

        var icon: String {
            switch self {
            case .builtin: return "doc.text.fill"
            case .mine:    return "person.crop.circle"
            }
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            searchBar

            Divider()

            HStack(spacing: 0) {
                // Category sidebar
                categorySidebar

                Divider()

                // Template grid
                templateGrid
            }

            Divider()

            // Footer
            footer
        }
        .frame(width: 520, height: 420)
        .onAppear { searchFocused = true }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.tertiary)
                .font(.system(size: 12))
            TextField(L("template.search"), text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($searchFocused)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .animation(DS.Motion.fast, value: query.isEmpty)
    }

    // MARK: - Category sidebar

    private var categorySidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(TemplateCategory.allCases, id: \.self) { cat in
                let count = templatesFor(cat).count
                if count > 0 || cat == .builtin {
                    CategoryRow(
                        icon: cat.icon,
                        label: cat.rawValue,
                        count: count,
                        isSelected: category == cat && query.isEmpty
                    )
                    .onTapGesture {
                        withAnimation(DS.Motion.fast) {
                            query = ""
                            category = cat
                        }
                    }
                }
            }
            Spacer()
        }
        .padding(.top, 8)
        .padding(.horizontal, 8)
        .frame(width: 130)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Template grid

    private var templateGrid: some View {
        let templates = query.isEmpty ? templatesFor(category) : allFiltered
        return Group {
            if templates.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text(L("common.noMatches"))
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 110, maximum: 140), spacing: 8)],
                        spacing: 8
                    ) {
                        ForEach(templates) { template in
                            TemplateCard(
                                template: template,
                                isSelected: selectedID == template.id,
                                onDelete: template.isBuiltin ? nil : {
                                    try? store.delete(id: template.id)
                                }
                            )
                            .onTapGesture {
                                withAnimation(DS.Motion.springFast) {
                                    selectedID = template.id
                                }
                            }
                            .onTapGesture(count: 2) {
                                selectedID = template.id
                                confirmSelection()
                            }
                        }
                    }
                    .padding(12)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            // Selected template preview name
            if let id = selectedID,
               let template = store.template(byID: id) {
                HStack(spacing: 6) {
                    Image(systemName: templateIcon(template))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(template.name)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(L("template.selectHint"))
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button(L("common.cancel")) { dismiss() }
                .keyboardShortcut(.escape, modifiers: [])

            Button(L("template.create")) { confirmSelection() }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
                .disabled(selectedID == nil)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Helpers

    private func templatesFor(_ cat: TemplateCategory) -> [DocumentTemplate] {
        switch cat {
        case .builtin: return store.builtinTemplates()
        case .mine:    return store.allTemplates().filter { !$0.isBuiltin }
        }
    }

    private var allFiltered: [DocumentTemplate] {
        let q = query.lowercased()
        return store.allTemplates().filter {
            $0.name.lowercased().contains(q) || $0.description.lowercased().contains(q)
        }
    }

    private func templateIcon(_ template: DocumentTemplate) -> String {
        template.isBuiltin ? "doc.text" : "doc.badge.plus"
    }

    private func confirmSelection() {
        guard let id = selectedID, let template = store.template(byID: id) else { return }
        onSelect(template)
        dismiss()
    }
}

// MARK: - Category Row

private struct CategoryRow: View {
    let icon: String
    let label: String
    let count: Int
    let isSelected: Bool

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .frame(width: 16, alignment: .center)

            Text(label)
                .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .lineLimit(1)

            Spacer()

            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        Capsule().fill(Color.primary.opacity(0.07))
                    )
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(
                    isSelected
                        ? Color.accentColor.opacity(0.12)
                        : isHovered ? Color.primary.opacity(0.06) : Color.clear
                )
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.1), value: isSelected)
        .animation(.easeOut(duration: 0.08), value: isHovered)
    }
}

// MARK: - Template Card

private struct TemplateCard: View {
    let template: DocumentTemplate
    let isSelected: Bool
    var onDelete: (() -> Void)? = nil

    @State private var isHovered = false

    private var cardIcon: String {
        // Map template name to a meaningful icon
        let name = template.name.lowercased()
        if name.contains("blank") || name.contains("空白") { return "doc" }
        if name.contains("meeting") || name.contains("会议") { return "person.2" }
        if name.contains("tech") || name.contains("技术") { return "cpu" }
        if name.contains("daily") || name.contains("日报") { return "calendar" }
        if name.contains("readme") { return "info.circle" }
        if name.contains("report") || name.contains("报告") { return "chart.bar.doc.horizontal" }
        return template.isBuiltin ? "doc.text" : "doc.badge.plus"
    }

    private var cardColor: Color {
        let name = template.name.lowercased()
        if name.contains("blank") || name.contains("空白") { return .gray }
        if name.contains("meeting") || name.contains("会议") { return .blue }
        if name.contains("tech") || name.contains("技术") { return .purple }
        if name.contains("daily") || name.contains("日报") { return .green }
        if name.contains("readme") { return .orange }
        if name.contains("report") || name.contains("报告") { return .indigo }
        return .accentColor
    }

    var body: some View {
        VStack(spacing: 8) {
            // Icon area
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        isSelected
                            ? cardColor.opacity(0.15)
                            : Color.primary.opacity(0.05)
                    )
                    .frame(height: 52)

                Image(systemName: cardIcon)
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(
                        isSelected ? cardColor : Color.secondary.opacity(0.6)
                    )
            }

            // Name
            Text(template.name)
                .font(.system(size: 11, weight: isSelected ? .medium : .regular))
                .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.7))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: .infinity)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            isSelected ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.08),
                            lineWidth: isSelected ? 1.5 : 1
                        )
                )
        )
        .overlay(alignment: .topTrailing) {
            if isHovered, let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .background(Circle().fill(Color(nsColor: .textBackgroundColor)))
                }
                .buttonStyle(.plain)
                .offset(x: 5, y: -5)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(DS.Motion.fast, value: isSelected)
        .animation(DS.Motion.micro, value: isHovered)
        .onHover { isHovered = $0 }
    }
}
