import SwiftUI

@MainActor
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
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
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
                .foregroundStyle(Color(nsColor: .systemOrange))
        } else {
            Image(systemName: iconName)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 12))
                .foregroundStyle(
                    isSelected
                        ? AnyShapeStyle(Color.appAccent.opacity(0.9))
                        : AnyShapeStyle(fileColor.opacity(0.75))
                )
        }
    }

    @ViewBuilder
    private var nameLabel: some View {
        if searchText.isEmpty {
            Text(item.name)
                .font(.system(size: 13, weight: isSelected ? .medium : .regular))
        } else {
            highlightedName
                .font(.system(size: 13))
        }
    }

    @ViewBuilder
    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(
                isSelected
                    // 跟随应用内强调色设置（Color.appAccent = system 蓝 / shadcn 单色），
                    // 不用 NSColor.selectedContentBackgroundColor——那是纯系统级颜色，
                    // 只跟 macOS 系统偏好设置的强调色走，不感知 App 内 aiAccentStyle
                    // 选择，会跟 LooseFileRow / AI 气泡等已经跟随 appAccent 的控件不一致。
                    ? AnyShapeStyle(Color.appAccent.opacity(0.16))
                    : isHovered
                        ? AnyShapeStyle(Color(nsColor: .unemphasizedSelectedContentBackgroundColor))
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
        return Text(before) + Text(match).foregroundColor(Color.appAccent).bold() + Text(after)
    }
}
