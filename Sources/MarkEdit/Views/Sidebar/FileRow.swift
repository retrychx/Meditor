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
                .font(.system(size: 13))
        } icon: {
            Image(systemName: item.isDirectory ? "folder.fill" : iconName)
                .foregroundStyle(item.isDirectory ? .primary : (isSelected ? Color(nsColor: .alternateSelectedControlTextColor) : fileColor))
                .font(.system(size: 11.5))
        }
        .contextMenu {
            if item.isDirectory {
                Button("New File") {
                    onAction?(.newFile(item.url))
                }
                Button("New Folder") {
                    onAction?(.newFolder(item.url))
                }
                Divider()
            }
            Button("Rename") {
                onAction?(.rename(item))
            }
            Button("Delete") {
                onAction?(.delete(item))
            }
            Divider()
            Button("Reveal in Finder") {
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
