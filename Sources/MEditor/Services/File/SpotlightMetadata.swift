import CoreSpotlight
import CryptoKit
import Foundation
import UniformTypeIdentifiers

// MARK: - Spotlight 元数据提取（纯逻辑，可测）

/// 单个 Markdown 文档进入 Spotlight 索引所需的元数据。
struct SpotlightDocumentMetadata: Equatable, Sendable {
    let title: String
    let contentDescription: String
    let textContent: String
}

enum SpotlightMetadata {

    /// textContent 截断上限：超长文档全量进索引会拖慢批量写入且收益递减。
    static let maxTextContentLength = 100_000
    /// contentDescription 截断上限（Spotlight 结果摘要只显示前几行）。
    static let maxDescriptionLength = 300

    /// domainIdentifier：同一工作区路径稳定复用同一 domain，
    /// 关闭/切换工作区时按 domain 精确清理，不影响其他工作区的索引项。
    static func domainIdentifier(forRoot root: URL) -> String {
        let path = root.standardizedFileURL.path
        let digest = SHA256.hash(data: Data(path.utf8))
        let hex = digest.prefix(8).map { String(format: "%02x", $0) }.joined()
        return "workspace-\(hex)"
    }

    /// CSSearchableItem 的 uniqueIdentifier：文件的绝对路径。
    /// 点击 Spotlight 结果时经 NSUserActivity 原样带回，用于打开对应文件。
    static func identifier(for url: URL) -> String {
        url.standardizedFileURL.path
    }

    /// 从 Markdown 原文提取索引元数据。
    /// - title: 第一个 H1（`# xxx`，跳过代码块）；无 H1 时回退文件名（去扩展名）。
    /// - contentDescription: 第一段非标题正文行，截断到 maxDescriptionLength。
    /// - textContent: 原文截断到 maxTextContentLength。
    static func extract(from markdown: String, fileName: String) -> SpotlightDocumentMetadata {
        SpotlightDocumentMetadata(
            title: firstH1(in: markdown) ?? fallbackTitle(from: fileName),
            contentDescription: firstParagraph(in: markdown),
            textContent: truncate(markdown, to: maxTextContentLength)
        )
    }

    static func fallbackTitle(from fileName: String) -> String {
        let stem = (fileName as NSString).deletingPathExtension
        return stem.isEmpty ? fileName : stem
    }

    /// 第一个 H1 标题文本（剥掉 `# ` 前缀与结尾闭合 `#`），跳过 fenced code block。
    static func firstH1(in markdown: String) -> String? {
        var fenceMarker: Character? = nil
        for line in markdown.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let marker = fenceMarker {
                // 闭合栅栏：整行由同一字符组成且长度 ≥ 3
                if trimmed.count >= 3, trimmed.allSatisfy({ $0 == marker }) { fenceMarker = nil }
                continue
            }
            if trimmed.hasPrefix("```") { fenceMarker = "`"; continue }
            if trimmed.hasPrefix("~~~") { fenceMarker = "~"; continue }
            guard trimmed.hasPrefix("# "), !trimmed.hasPrefix("## ") else { continue }
            var text = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            while text.hasSuffix("#") { text.removeLast() }
            text = text.trimmingCharacters(in: .whitespaces)
            if !text.isEmpty { return text }
        }
        return nil
    }

    /// 第一段正文：跳过空行、标题行与栅栏定界行，取第一行非空内容并截断。
    static func firstParagraph(in markdown: String) -> String {
        for line in markdown.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix("#") { continue }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") { continue }
            return truncate(trimmed, to: maxDescriptionLength)
        }
        return ""
    }

    static func truncate(_ text: String, to maxLength: Int) -> String {
        text.count > maxLength ? String(text.prefix(maxLength)) : text
    }
}

// MARK: - 索引项构造（纯逻辑，可测）

enum SpotlightItemBuilder {

    static let markdownContentType: UTType = {
        UTType("net.daringfireball.markdown") ?? .plainText
    }()

    static func makeItem(
        url: URL,
        domainIdentifier: String,
        metadata: SpotlightDocumentMetadata,
        contentModificationDate: Date? = nil
    ) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: markdownContentType)
        attributes.title = metadata.title
        attributes.contentDescription = metadata.contentDescription
        attributes.textContent = metadata.textContent
        attributes.contentModificationDate = contentModificationDate
        return CSSearchableItem(
            uniqueIdentifier: SpotlightMetadata.identifier(for: url),
            domainIdentifier: domainIdentifier,
            attributeSet: attributes
        )
    }
}

// MARK: - 增量 diff（纯逻辑，可测）

enum SpotlightIndexDiffer {

    /// 对比磁盘快照与已索引状态，产出需要 upsert / delete 的 identifier 列表。
    /// modDate 变化即视为需要重建该文件索引项；已消失的 identifier 需要删除。
    static func diff(
        disk: [String: Date?],
        indexed: [String: Date?]
    ) -> (upsert: [String], delete: [String]) {
        let delete = indexed.keys.filter { disk[$0] == nil }.sorted()
        let upsert = disk.keys.filter { indexed[$0] != disk[$0] }.sorted()
        return (upsert, delete)
    }
}
