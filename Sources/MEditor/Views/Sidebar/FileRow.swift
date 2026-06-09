import SwiftUI

struct FileRow: View {
    let item: FileItem
    let isSelected: Bool
    let onAction: ((FileAction) -> Void)?

    init(item: FileItem, isSelected: Bool = false, onAction: ((FileAction) -> Void)? = nil) {
        self.item = item
        self.isSelected = isSelected
        self.onAction = onAction
    }

    var body: some View {
        Label {
            Text(item.name)
                .font(.system(size: 12.5))
                .lineLimit(1)
                .truncationMode(.middle)
        } icon: {
            Image(systemName: item.isDirectory ? "folder.fill" : iconName)
                .foregroundStyle(item.isDirectory ? .orange : .secondary)
                .font(.system(size: 11))
        }
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
}
