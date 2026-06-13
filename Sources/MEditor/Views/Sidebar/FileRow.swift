import SwiftUI

struct FileRow: View {
    let item: FileItem
    let isSelected: Bool
    let searchText: String
    let onAction: ((FileAction) -> Void)?

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
        HStack(spacing: 6) {
            fileIcon
                .frame(width: 15, alignment: .center)

            nameLabel
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(rowBackground)
        // Left accent line via overlay — avoids affecting List layout
        .overlay(alignment: .leading) {
            if isSelected {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.accentColor)
                    .frame(width: 2.5)
                    .padding(.vertical, 7)
                    .transition(.opacity)
                    .animation(.easeOut(duration: 0.12), value: isSelected)
            }
        }
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
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.orange)
        } else {
            Image(systemName: iconName)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(fileColor)
        }
    }

    @ViewBuilder
    private var nameLabel: some View {
        if searchText.isEmpty {
            Text(item.name)
                .font(.system(size: 12.5, weight: isSelected ? .medium : .regular))
                .foregroundStyle(isSelected
                    ? AnyShapeStyle(Color.primary)
                    : AnyShapeStyle(Color.primary.opacity(0.78))
                )
        } else {
            highlightedName
                .font(.system(size: 12.5))
        }
    }

    @ViewBuilder
    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(
                isSelected
                    ? AnyShapeStyle(.tint.opacity(0.13))
                    : isHovered
                        ? AnyShapeStyle(Color.primary.opacity(0.055))
                        : AnyShapeStyle(Color.clear)
            )
            .animation(.easeOut(duration: 0.1), value: isSelected)
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
