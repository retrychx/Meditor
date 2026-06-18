import Foundation

// MARK: - Category

enum TemplateCategory: String, Codable {
    case markdown   // 用于新建 Markdown 文档
    case htmlTheme  // 用于 HTML 美化输出
    case user       // 用户自定义
}

// MARK: - Model

struct DocumentTemplate: Identifiable, Equatable {
    let id: String
    let name: String
    let description: String
    let content: String
    let isBuiltin: Bool
    let createdAt: Date
    let fileExtension: String   // "md" or "html"
    let category: TemplateCategory

    var fileName: String { id + "." + fileExtension }

    init(
        id: String, name: String, description: String, content: String,
        isBuiltin: Bool, createdAt: Date, fileExtension: String,
        category: TemplateCategory = .markdown
    ) {
        self.id = id; self.name = name; self.description = description
        self.content = content; self.isBuiltin = isBuiltin
        self.createdAt = createdAt; self.fileExtension = fileExtension
        self.category = category
    }
}

// MARK: - Protocol (testable)

protocol TemplateStoreProtocol {
    func allTemplates() -> [DocumentTemplate]
    func builtinTemplates() -> [DocumentTemplate]
    func userTemplates() -> [DocumentTemplate]
    func htmlThemeTemplates() -> [DocumentTemplate]
    func template(byID id: String) -> DocumentTemplate?
    func save(name: String, content: String) throws -> DocumentTemplate
    func delete(id: String) throws
}

// MARK: - Errors

enum TemplateStoreError: LocalizedError {
    case cannotDeleteBuiltin
    case invalidName
    case writeFailed(Error)

    var errorDescription: String? {
        switch self {
        case .cannotDeleteBuiltin: return "Built-in templates cannot be deleted"
        case .invalidName: return "Template name is invalid"
        case .writeFailed(let e): return "Failed to save template: \(e.localizedDescription)"
        }
    }
}

// MARK: - Implementation

final class TemplateStore: TemplateStoreProtocol {
    private let userDir: URL
    private var cachedUserTemplates: [DocumentTemplate]?

    init(baseDir: URL? = nil) {
        let base = baseDir ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.userDir = base.appendingPathComponent("MEditor/templates", isDirectory: true)
        ensureDirectory()
    }

    // MARK: - Read

    func allTemplates() -> [DocumentTemplate] {
        builtinTemplates() + userTemplates()
    }

    func builtinTemplates() -> [DocumentTemplate] {
        Self.builtins
    }

    func userTemplates() -> [DocumentTemplate] {
        if let cached = cachedUserTemplates { return cached }
        let templates = loadUserTemplates()
        cachedUserTemplates = templates
        return templates
    }

    func htmlThemeTemplates() -> [DocumentTemplate] {
        builtinTemplates().filter { $0.category == .htmlTheme }
    }

    func template(byID id: String) -> DocumentTemplate? {
        allTemplates().first { $0.id == id }
    }

    // MARK: - Write

    @discardableResult
    func save(name: String, content: String) throws -> DocumentTemplate {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 100 else { throw TemplateStoreError.invalidName }

        let slug = Self.slugify(trimmed)
        let template = DocumentTemplate(
            id: slug,
            name: trimmed,
            description: String(content.prefix(80)).replacingOccurrences(of: "\n", with: " "),
            content: content,
            isBuiltin: false,
            createdAt: Date(),
            fileExtension: "md",
            category: .user
        )

        let fileURL = userDir.appendingPathComponent(template.fileName)
        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            throw TemplateStoreError.writeFailed(error)
        }

        let meta = TemplateMeta(name: trimmed, description: template.description, createdAt: template.createdAt)
        let metaURL = userDir.appendingPathComponent(slug + ".json")
        if let data = try? JSONEncoder().encode(meta) {
            try? data.write(to: metaURL, options: .atomic)
        }

        cachedUserTemplates = nil
        return template
    }

    func delete(id: String) throws {
        guard !(Self.builtins.contains { $0.id == id }) else {
            throw TemplateStoreError.cannotDeleteBuiltin
        }
        let fm = FileManager.default
        let mdURL = userDir.appendingPathComponent(id + ".md")
        let metaURL = userDir.appendingPathComponent(id + ".json")
        try? fm.removeItem(at: mdURL)
        try? fm.removeItem(at: metaURL)
        cachedUserTemplates = nil
    }

    // MARK: - Private

    private func ensureDirectory() {
        try? FileManager.default.createDirectory(at: userDir, withIntermediateDirectories: true)
    }

    private func loadUserTemplates() -> [DocumentTemplate] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: userDir, includingPropertiesForKeys: nil) else { return [] }
        let mdFiles = files.filter { $0.pathExtension == "md" }

        return mdFiles.compactMap { url -> DocumentTemplate? in
            let slug = url.deletingPathExtension().lastPathComponent
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }

            let metaURL = userDir.appendingPathComponent(slug + ".json")
            let meta = (try? JSONDecoder().decode(TemplateMeta.self, from: Data(contentsOf: metaURL))) ?? TemplateMeta(
                name: slug.replacingOccurrences(of: "-", with: " ").capitalized,
                description: String(content.prefix(80)).replacingOccurrences(of: "\n", with: " "),
                createdAt: (try? fm.attributesOfItem(atPath: url.path)[.creationDate] as? Date) ?? Date()
            )

            return DocumentTemplate(
                id: slug,
                name: meta.name,
                description: meta.description,
                content: content,
                isBuiltin: false,
                createdAt: meta.createdAt,
                fileExtension: "md",
                category: .user
            )
        }.sorted { $0.createdAt > $1.createdAt }
    }

    private static func slugify(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: "-"))
        let slug = name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .unicodeScalars.filter { allowed.contains($0) }
            .map { Character($0) }
        let result = String(slug.prefix(50))
        return result.isEmpty ? "untitled-\(Int(Date().timeIntervalSince1970))" : result
    }

    // MARK: - Built-in templates

    static var builtins: [DocumentTemplate] {[
        DocumentTemplate(id: "blank",        name: L("template.blank"),      description: L("template.blankDesc"),      content: "",                             isBuiltin: true, createdAt: .distantPast, fileExtension: "md",   category: .markdown),
        DocumentTemplate(id: "meeting-notes",name: L("template.meeting"),    description: L("template.meetingDesc"),    content: BuiltinTemplates.meeting,       isBuiltin: true, createdAt: .distantPast, fileExtension: "md",   category: .markdown),
        DocumentTemplate(id: "tech-design",  name: L("template.techDesign"), description: L("template.techDesignDesc"), content: BuiltinTemplates.techDesign,    isBuiltin: true, createdAt: .distantPast, fileExtension: "md",   category: .markdown),
        DocumentTemplate(id: "weekly-report",name: L("template.weekly"),     description: L("template.weeklyDesc"),     content: BuiltinTemplates.weekly,        isBuiltin: true, createdAt: .distantPast, fileExtension: "md",   category: .markdown),
        DocumentTemplate(id: "journal",      name: L("template.journal"),    description: L("template.journalDesc"),    content: BuiltinTemplates.journal,       isBuiltin: true, createdAt: .distantPast, fileExtension: "md",   category: .markdown),
        DocumentTemplate(id: "html-doc",     name: L("template.htmlDoc"),    description: L("template.htmlDocDesc"),    content: htmlDocFromBundle,              isBuiltin: true, createdAt: .distantPast, fileExtension: "html", category: .htmlTheme),
        DocumentTemplate(id: "html-tufte",   name: "Tufte 学术风",            description: "衬线字体・学术风格",           content: BuiltinTemplates.htmlTufte,    isBuiltin: true, createdAt: .distantPast, fileExtension: "html", category: .htmlTheme),
        DocumentTemplate(id: "html-craft",   name: "Craft 现代风",            description: "卡片布局・现代简洁",           content: BuiltinTemplates.htmlCraft,    isBuiltin: true, createdAt: .distantPast, fileExtension: "html", category: .htmlTheme),
        DocumentTemplate(id: "html-dark",    name: "Dark 代码风",             description: "深色主题・技术风格",           content: BuiltinTemplates.htmlDark,     isBuiltin: true, createdAt: .distantPast, fileExtension: "html", category: .htmlTheme),
    ]}

    private static var htmlDocFromBundle: String {
        let mainURL = Bundle.main.bundleURL
        let candidates = [
            mainURL.appendingPathComponent("MEditor_MEditor.bundle/Resources/Templates/doc-template.html"),
            mainURL.appendingPathComponent("Contents/Resources/Templates/doc-template.html"),
            mainURL.deletingLastPathComponent().appendingPathComponent("MEditor_MEditor.bundle/Resources/Templates/doc-template.html"),
        ]
        for url in candidates {
            if let content = try? String(contentsOf: url, encoding: .utf8) { return content }
        }
        return "<!DOCTYPE html>\n<html>\n<head><title>Document</title></head>\n<body>\n<h1>Title</h1>\n</body>\n</html>"
    }
}

// MARK: - Metadata DTO

private struct TemplateMeta: Codable {
    let name: String
    let description: String
    let createdAt: Date
}
