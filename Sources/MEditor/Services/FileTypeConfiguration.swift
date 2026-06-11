import SwiftUI

struct FileTypeDescriptor {
    let extensions: Set<String>
    let icon: String
    let color: Color
    let editorLanguage: EditorLanguage?
    let isPreviewSupported: Bool

    init(extensions: Set<String>, icon: String, color: Color = .secondary, editorLanguage: EditorLanguage? = nil, isPreviewSupported: Bool = false) {
        self.extensions = extensions
        self.icon = icon
        self.color = color
        self.editorLanguage = editorLanguage
        self.isPreviewSupported = isPreviewSupported
    }
}

final class FileTypeConfiguration {
    static let shared = FileTypeConfiguration()

    private var types: [FileTypeDescriptor] = [
        .init(extensions: ["md", "markdown"], icon: "doc.text.fill", color: Color(red: 0.38, green: 0.54, blue: 0.72), editorLanguage: .markdown, isPreviewSupported: true),
        .init(extensions: ["html", "htm"], icon: "globe", color: Color(red: 0.68, green: 0.48, blue: 0.40), editorLanguage: .html, isPreviewSupported: true),
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

    func color(for ext: String) -> Color {
        descriptor(for: ext).color
    }

    private let defaultDescriptor = FileTypeDescriptor(
        extensions: [],
        icon: "doc.fill",
        color: .secondary,
        editorLanguage: nil
    )
}
