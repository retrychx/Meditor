import SwiftUI

/// Template picker presented as a sheet when creating a new file (⌘N).
struct TemplatePickerSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    let store: TemplateStoreProtocol
    let onSelect: (DocumentTemplate) -> Void

    @State private var query = ""
    @State private var selectedID: String? = "blank"
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 480, height: 400)
        .onAppear { searchFocused = true }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 12))
            TextField(L("template.search"), text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($searchFocused)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Content

    private var filteredTemplates: [DocumentTemplate] {
        let all = store.allTemplates()
        guard !query.isEmpty else { return all }
        let q = query.lowercased()
        return all.filter { $0.name.lowercased().contains(q) || $0.description.lowercased().contains(q) }
    }

    private var content: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if !store.builtinTemplates().isEmpty {
                    sectionHeader("Built-in")
                    ForEach(filteredBuiltin) { t in templateRow(t) }
                }
                let user = filteredUser
                if !user.isEmpty {
                    sectionHeader(L("template.myTemplates"))
                    ForEach(user) { t in templateRow(t) }
                }
                if filteredTemplates.isEmpty {
                    Text(L("common.noMatches"))
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 40)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var filteredBuiltin: [DocumentTemplate] {
        filteredTemplates.filter(\.isBuiltin)
    }

    private var filteredUser: [DocumentTemplate] {
        filteredTemplates.filter { !$0.isBuiltin }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }

    private func templateRow(_ template: DocumentTemplate) -> some View {
        HStack(spacing: 10) {
            Image(systemName: template.isBuiltin ? "doc.text" : "doc.badge.plus")
                .font(.system(size: 12))
                .foregroundStyle(selectedID == template.id ? Color.accentColor : .secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(template.name)
                    .font(.system(size: 13, weight: selectedID == template.id ? .medium : .regular))
                Text(template.description)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer()

            if !template.isBuiltin {
                Button {
                    try? (store as? TemplateStore)?.delete(id: template.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help(L("common.delete"))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(selectedID == template.id ? Color.accentColor.opacity(0.1) : Color.clear)
                .padding(.horizontal, 6)
        )
        .contentShape(Rectangle())
        .onTapGesture { selectedID = template.id }
        .onTapGesture(count: 2) {
            selectedID = template.id
            confirmSelection()
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button(L("common.cancel")) { dismiss() }
                .keyboardShortcut(.escape, modifiers: [])
            Spacer()
            Button(L("template.create")) { confirmSelection() }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
                .disabled(selectedID == nil)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func confirmSelection() {
        guard let id = selectedID, let template = store.template(byID: id) else { return }
        onSelect(template)
        dismiss()
    }
}
