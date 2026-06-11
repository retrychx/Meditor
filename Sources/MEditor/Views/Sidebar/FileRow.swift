import SwiftUI

struct FileRow: View {
    let item: FileItem
    let isSelected: Bool
    let searchText: String
    let onAction: ((FileAction) -> Void)?

    init(item: FileItem, isSelected: Bool = false, searchText: String = "", onAction: ((FileAction) -> Void)? = nil) {
        self.item = item
        self.isSelected = isSelected
        self.searchText = searchText
        self.onAction = onAction
    }

    var body: some View {
        Label {
            if searchText.isEmpty {
                Text(item.name)
                    .font(.system(size: 12.5))
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                highlightedName
                    .font(.system(size: 12.5))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        } icon: {
            Image(systemName: item.isDirectory ? "folder" : iconName)
                .foregroundStyle(item.isDirectory ? .orange : .secondary)
                .font(.system(size: 11))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
        )
        .contextMenu {
            if item.isDirectory {
                Button(L("menu.newFile")) {
                    onAction?(.newFile(item.url))
                }
                Button(L("menu.newFolder")) {
                    onAction?(.newFolder(item.url))
                }
                Divider()
            }
            Button(L("rename.title")) {
                onAction?(.rename(item))
            }
            Button(L("common.delete")) {
                onAction?(.delete(item))
            }
            Divider()
            Button(L("menu.copyAbsolutePath")) {
                onAction?(.copyAbsolutePath(item))
            }
            Button(L("menu.copyRelativePath")) {
                onAction?(.copyRelativePath(item))
            }
            Divider()
            Button(L("menu.revealInFinder")) {
                onAction?(.revealInFinder(item))
            }
        }
    }

    private var iconName: String {
        FileTypeConfiguration.shared.icon(for: item.fileExtension)
    }

    private var fileColor: Color {
        FileTypeConfiguration.shared.color(for: item.fileExtension)
    }

    private var highlightedName: Text {
        let name = item.name
        let lower = name.lowercased()
        let query = searchText.lowercased()
        guard let range = lower.range(of: query) else {
            return Text(name)
        }
        let before = String(name[name.startIndex..<range.lowerBound])
        let match = String(name[range.lowerBound..<range.upperBound])
        let after = String(name[range.upperBound...])
        return Text(before) + Text(match).foregroundColor(.accentColor).bold() + Text(after)
    }
}
