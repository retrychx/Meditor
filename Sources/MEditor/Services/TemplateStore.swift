import Foundation

// MARK: - Model

struct DocumentTemplate: Identifiable, Equatable {
    let id: String
    let name: String
    let description: String
    let content: String
    let isBuiltin: Bool
    let createdAt: Date
    let fileExtension: String  // "md" or "html"

    var fileName: String { id + "." + fileExtension }
}

// MARK: - Protocol (testable)

protocol TemplateStoreProtocol {
    func allTemplates() -> [DocumentTemplate]
    func builtinTemplates() -> [DocumentTemplate]
    func userTemplates() -> [DocumentTemplate]
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
            fileExtension: "md"
        )

        // Write content
        let fileURL = userDir.appendingPathComponent(template.fileName)
        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            throw TemplateStoreError.writeFailed(error)
        }

        // Write metadata
        let meta = TemplateMeta(name: trimmed, description: template.description, createdAt: template.createdAt)
        let metaURL = userDir.appendingPathComponent(slug + ".json")
        if let data = try? JSONEncoder().encode(meta) {
            try? data.write(to: metaURL, options: .atomic)
        }

        cachedUserTemplates = nil // invalidate cache
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

            // Try loading metadata
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
                fileExtension: "md"
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
        DocumentTemplate(id: "blank", name: L("template.blank"), description: L("template.blankDesc"), content: "", isBuiltin: true, createdAt: .distantPast, fileExtension: "md"),
        DocumentTemplate(id: "meeting-notes", name: L("template.meeting"), description: L("template.meetingDesc"), content: meetingTemplate, isBuiltin: true, createdAt: .distantPast, fileExtension: "md"),
        DocumentTemplate(id: "tech-design", name: L("template.techDesign"), description: L("template.techDesignDesc"), content: techDesignTemplate, isBuiltin: true, createdAt: .distantPast, fileExtension: "md"),
        DocumentTemplate(id: "weekly-report", name: L("template.weekly"), description: L("template.weeklyDesc"), content: weeklyTemplate, isBuiltin: true, createdAt: .distantPast, fileExtension: "md"),
        DocumentTemplate(id: "journal", name: L("template.journal"), description: L("template.journalDesc"), content: journalTemplate, isBuiltin: true, createdAt: .distantPast, fileExtension: "md"),
        DocumentTemplate(id: "html-doc", name: L("template.htmlDoc"), description: L("template.htmlDocDesc"), content: htmlDocTemplate, isBuiltin: true, createdAt: .distantPast, fileExtension: "html"),
    ]}

    private static var datePlaceholder: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Date())
    }

    private static var htmlDocTemplate: String {
        // Try multiple paths: SPM resource bundle (debug) + packaged .app
        let mainURL = Bundle.main.bundleURL
        let candidates = [
            mainURL.appendingPathComponent("MEditor_MEditor.bundle/Resources/Templates/doc-template.html"),
            mainURL.appendingPathComponent("Contents/Resources/Templates/doc-template.html"),
            mainURL.deletingLastPathComponent().appendingPathComponent("MEditor_MEditor.bundle/Resources/Templates/doc-template.html"),
        ]
        for url in candidates {
            if let content = try? String(contentsOf: url, encoding: .utf8) {
                return content
            }
        }
        return "<!DOCTYPE html>\n<html>\n<head><title>Document</title></head>\n<body>\n<h1>Title</h1>\n</body>\n</html>"
    }

    private static var meetingTemplate: String { """
    # Meeting Notes

    **Date:** \(datePlaceholder)
    **Attendees:**

    - [ ] Name 1
    - [ ] Name 2

    ## Agenda

    1.

    ## Discussion

    ## Action Items

    | Owner | Task | Due |
    |-------|------|-----|
    |       |      |     |
    """ }

    private static var techDesignTemplate: String { """
    # Technical Design

    ## Background

    ## Goals

    - [ ]

    ## Non-Goals

    -

    ## Design

    ### Architecture

    ### API

    ### Data Model

    ## Implementation Plan

    | Phase | Task | Estimate |
    |-------|------|----------|
    | 1     |      |          |

    ## Risks

    ## Open Questions
    """ }

    private static var weeklyTemplate: String { """
    # Weekly Report

    **Week of:** \(datePlaceholder)

    ## Done This Week

    -

    ## In Progress

    -

    ## Blockers

    -

    ## Plan for Next Week

    -

    ## Notes
    """ }

    private static var journalTemplate: String { """
    # \(datePlaceholder)

    ## Today's Focus

    -

    ## Notes

    ## Learnings

    ## Tomorrow
    """ }
}

// MARK: - Metadata DTO

private struct TemplateMeta: Codable {
    let name: String
    let description: String
    let createdAt: Date
}
