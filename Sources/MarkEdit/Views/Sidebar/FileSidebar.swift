import SwiftUI

struct FileSidebar: View {
    @Environment(AppState.self) private var state

    var body: some View {
        List(state.fileTree, id: \.id, children: \.children, selection: Binding(
            get: { state.selectedFileID },
            set: { newID in
                state.selectedFileID = newID
                if let id = newID,
                   let item = findItem(by: id, in: state.fileTree),
                   !item.isDirectory {
                    state.openFile(item)
                }
            }
        )) { item in
            FileRow(item: item)
                .help(item.url.path)
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .frame(minWidth: 200)
    }

    private func findItem(by id: UUID, in items: [FileItem]) -> FileItem? {
        for item in items {
            if item.id == id { return item }
            if let children = item.children, let found = findItem(by: id, in: children) {
                return found
            }
        }
        return nil
    }
}

// MARK: - File Row

private struct FileRow: View {
    let item: FileItem

    var body: some View {
        Label(item.name, systemImage: item.isDirectory ? "folder.fill" : fileIcon)
            .font(.system(size: 13))
            .foregroundStyle(item.isDirectory ? AnyShapeStyle(.primary) : AnyShapeStyle(fileColor))
    }

    private var fileIcon: String {
        switch item.extension {
        case "md", "markdown": return "doc.text"
        case "html", "htm": return "doc.richtext"
        case "css": return "paintbrush"
        case "js": return "doc.append"
        default: return "doc"
        }
    }

    private var fileColor: some ShapeStyle {
        switch item.extension {
        case "md", "markdown": Color(red: 0.35, green: 0.55, blue: 0.75)
        case "html", "htm":   Color(red: 0.75, green: 0.45, blue: 0.35)
        case "css":           Color(red: 0.55, green: 0.45, blue: 0.75)
        case "js":            Color(red: 0.75, green: 0.65, blue: 0.28)
        default:              Color.secondary
        }
    }
}
