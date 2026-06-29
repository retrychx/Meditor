import Foundation

/// 递归扫描工作区 .md 文件，提取 `- [ ]` / `- [x]` checkbox 条目。
enum TodoScanner {
    private static let pattern: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(
            pattern: #"^(?:\s*)- \[(x| )\] (.+)$"#,
            options: [.anchorsMatchLines]
        )
    }()

    /// 异步扫描工作区，返回所有待办条目。
    static func scan(rootURL: URL) async -> [TodoItem] {
        await Task.detached(priority: .userInitiated) {
            var items: [TodoItem] = []
            let fm = FileManager.default
            guard let enumerator = fm.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { return [] }

            for case let url as URL in enumerator {
                guard url.pathExtension.lowercased() == "md",
                      let res = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                      res.isRegularFile == true else { continue }
                guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }

                let lines = content.components(separatedBy: "\n")
                for (lineIndex, line) in lines.enumerated() {
                    let nsLine = line as NSString
                    let range = NSRange(location: 0, length: nsLine.length)
                    guard let match = pattern.firstMatch(in: line, range: range),
                          match.numberOfRanges == 3 else { continue }

                    let checkboxRange = match.range(at: 1)
                    let textRange = match.range(at: 2)
                    guard checkboxRange.location != NSNotFound,
                          textRange.location != NSNotFound else { continue }

                    let checkbox = nsLine.substring(with: checkboxRange)
                    let text = nsLine.substring(with: textRange)
                    items.append(TodoItem(
                        id: UUID(),
                        text: text,
                        isChecked: checkbox == "x",
                        fileURL: url,
                        lineIndex: lineIndex
                    ))
                }
            }
            return items
        }.value
    }

    /// 在文件的指定行切换 checkbox 状态（`- [ ]` ↔ `- [x]`），然后写回文件。
    static func toggle(item: TodoItem) throws {
        var lines = (try String(contentsOf: item.fileURL, encoding: .utf8))
            .components(separatedBy: "\n")
        guard item.lineIndex < lines.count else { return }

        let original = lines[item.lineIndex]
        let updated: String
        if item.isChecked {
            updated = original.replacingOccurrences(of: "- [x] ", with: "- [ ] ")
                              .replacingOccurrences(of: "- [X] ", with: "- [ ] ")
        } else {
            updated = original.replacingOccurrences(of: "- [ ] ", with: "- [x] ")
        }
        lines[item.lineIndex] = updated
        try lines.joined(separator: "\n").write(to: item.fileURL, atomically: true, encoding: .utf8)
    }
}
