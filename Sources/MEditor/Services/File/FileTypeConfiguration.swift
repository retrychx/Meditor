import Foundation

struct FileTypeDescriptor {
    let extensions: Set<String>
    let icon: String
    let colorHex: String  // platform-agnostic hex, e.g. "#6189B8"
    let editorLanguage: EditorLanguage?
    let isPreviewSupported: Bool

    init(extensions: Set<String>, icon: String, colorHex: String = "#8E8E93", editorLanguage: EditorLanguage? = nil, isPreviewSupported: Bool = false) {
        self.extensions = extensions
        self.icon = icon
        self.colorHex = colorHex
        self.editorLanguage = editorLanguage
        self.isPreviewSupported = isPreviewSupported
    }
}

/// 文件类型注册表。`types` 仅在启动期 `register` 时写入、之后只读；
/// 标注 @unchecked Sendable 以允许跨 actor 引用共享实例（Swift 6 并发检查要求）。
final class FileTypeConfiguration: @unchecked Sendable {
    static let shared = FileTypeConfiguration()

    private var types: [FileTypeDescriptor] = [
        .init(extensions: ["md", "markdown"], icon: "doc.text", colorHex: "#618AB8", editorLanguage: .markdown, isPreviewSupported: true),
        .init(extensions: ["html", "htm"], icon: "globe", colorHex: "#AD7A66", editorLanguage: .html, isPreviewSupported: true),
    ]

    private init() {}

    func register(_ type: FileTypeDescriptor) {
        types.append(type)
    }

    func descriptor(for ext: String) -> FileTypeDescriptor {
        types.first { $0.extensions.contains(ext.lowercased()) } ?? defaultDescriptor
    }

    var supportedExtensions: Set<String> {
        Set(types.flatMap(\.extensions))
    }

    var supportedPreviewExtensions: Set<String> {
        Set(types.filter(\.isPreviewSupported).flatMap(\.extensions))
    }

    func editorLanguage(for ext: String) -> EditorLanguage? {
        descriptor(for: ext).editorLanguage
    }

    func icon(for ext: String) -> String {
        descriptor(for: ext).icon
    }

    func color(for ext: String) -> String {
        descriptor(for: ext).colorHex
    }

    private let defaultDescriptor = FileTypeDescriptor(
        extensions: [],
        icon: "doc",
        colorHex: "#8E8E93",
        editorLanguage: nil
    )
}
