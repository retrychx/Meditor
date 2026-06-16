import SwiftUI

struct FileRow: View {
    let item: FileItem
    let isSelected: Bool
    let searchText: String
    let onAction: ((FileAction) -> Void)?

    @Environment(AppState.self) private var state
    @State private var isHovered = false

    init(
        item: FileItem,
        isSelected: Bool = false,
        searchText: String = "",
        onAction: ((FileAction) -> Void)? = nil
    ) {
        self.item       = item
        self.isSelected = isSelected
        self.searchText = searchText
        self.onAction   = onAction
    }

    var body: some View {
        HStack(spacing: 7) {
            fileIcon
                .frame(width: 16, alignment: .center)

            nameLabel
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Modified indicator — subtle dot on the right
            if !item.isDirectory {
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
        .frame(minHeight: 30)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .contextMenu { contextMenuItems }
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var fileIcon: some View {
        if item.isDirectory {
            Image(systemName: "folder.fill")
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 13))
                .foregroundStyle(Color.orange.opacity(0.85))
        } else {
            Image(systemName: iconName)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 12))
                .foregroundStyle(
                    isSelected
                        ? AnyShapeStyle(Color.accentColor.opacity(0.9))
                        : AnyShapeStyle(fileColor.opacity(0.75))
                )
        }
    }

    @ViewBuilder
    private var nameLabel: some View {
        let theme = state.themeStore.current
        if searchText.isEmpty {
            Text(item.name)
                .font(.system(size: 12.5, weight: isSelected ? .medium : .regular))
                // Craft token: selected uses primary text, others use slightly muted
                .foregroundStyle(
                    isSelected
                        ? AnyShapeStyle(theme.craftPrimary)
                        : AnyShapeStyle(theme.craftPrimary.opacity(0.72))
                )
        } else {
            highlightedName
                .font(.system(size: 12.5))
        }
    }

    @ViewBuilder
    private var rowBackground: some View {
        // Native sidebar-style selection: a subtle neutral highlight that reads
        // well on the translucent material, no white pill / drop shadow.
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(
                isSelected
                    ? AnyShapeStyle(Color.primary.opacity(0.10))
                    : isHovered
                        ? AnyShapeStyle(Color.primary.opacity(0.05))
                        : AnyShapeStyle(Color.clear)
            )
            .padding(.horizontal, 4)
            .animation(.easeOut(duration: 0.09), value: isSelected)
            .animation(.easeOut(duration: 0.07), value: isHovered)
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        if item.isDirectory {
            Button(L("menu.newFile"))   { onAction?(.newFile(item.url)) }
            Button(L("menu.newFolder")) { onAction?(.newFolder(item.url)) }
            Divider()
        }
        Button(L("rename.title"))  { onAction?(.rename(item)) }
        Button(L("common.delete")) { onAction?(.delete(item)) }
        Divider()
        Button(L("menu.copyAbsolutePath")) { onAction?(.copyAbsolutePath(item)) }
        Button(L("menu.copyRelativePath")) { onAction?(.copyRelativePath(item)) }
        Divider()
        Button(L("menu.revealInFinder"))   { onAction?(.revealInFinder(item)) }
    }

    // MARK: - Helpers

    private var iconName: String {
        FileTypeConfiguration.shared.icon(for: item.fileExtension)
    }

    private var fileColor: Color {
        Color(hex: FileTypeConfiguration.shared.color(for: item.fileExtension))
    }

    private var highlightedName: Text {
        let name = item.name
        guard let range = name.range(of: searchText, options: .caseInsensitive) else {
            return Text(name)
        }
        let before = String(name[name.startIndex..<range.lowerBound])
        let match  = String(name[range])
        let after  = String(name[range.upperBound...])
        return Text(before) + Text(match).foregroundColor(.accentColor).bold() + Text(after)
    }
}
