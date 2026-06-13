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
        HStack(spacing: 0) {
            // Selection accent line
            SelectionAccentLine(verticalPad: 7)
                .opacity(isSelected ? 1 : 0)
                .animation(DS.Motion.springFast, value: isSelected)

            HStack(spacing: 5) {
                // File icon
                fileIcon
                    .frame(width: 14, alignment: .center)

                // File name
                nameLabel
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.leading, 6)
            .padding(.trailing, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
        .onHover { isHovered = $0 }
        .contextMenu { contextMenuItems }
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var fileIcon: some View {
        if item.isDirectory {
            Image(systemName: "folder.fill")
                .font(.system(size: 11.5, weight: .regular))
                .foregroundStyle(.orange.opacity(0.85))
        } else {
            Image(systemName: iconName)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(fileColor.opacity(0.9))
        }
    }

    @ViewBuilder
    private var nameLabel: some View {
        if searchText.isEmpty {
            Text(item.name)
                .font(DS.Font.label(12.5, weight: isSelected ? .medium : .regular))
                .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.primary.opacity(0.82)))
        } else {
            highlightedName
                .font(DS.Font.label(12.5))
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: DS.Radius.sm)
            .fill(
                isSelected
                    ? DS.Color.rowSelected
                    : isHovered ? DS.Color.rowHover : Color.clear
            )
            .animation(DS.Motion.fast, value: isSelected)
            .animation(DS.Motion.micro, value: isHovered)
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
        return Text(before)
            + Text(match).foregroundColor(.accentColor).bold()
            + Text(after)
    }
}
