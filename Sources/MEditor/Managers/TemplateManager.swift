import Foundation
import Observation

/// Owns all template-related state and operations.
///
/// Extracted from AppState to keep AppState a thin facade. AppState holds
/// a `templateManager` reference and forwards template-related view bindings
/// to it (showingPicker, showingSaveAs, etc.).
@MainActor
@Observable
final class TemplateManager {

    // MARK: - UI State

    /// Whether the template picker sheet is visible.
    var showingPicker = false
    /// Whether the "save as template" alert is visible.
    var showingSaveAs = false
    /// Name input for the "save as template" alert.
    var saveAsName = ""

    // MARK: - Internal

    /// Target directory for the next createFromTemplate call.
    /// Set by the sidebar before opening the picker; consumed and cleared
    /// in createFromTemplate. Nil means "use project root".
    var pendingParentURL: URL?

    // MARK: - Store

    let store: TemplateStoreProtocol

    // MARK: - Init

    init(store: TemplateStoreProtocol = TemplateStore()) {
        self.store = store
    }

    // MARK: - Actions

    /// Create a new file from a template.
    /// - Parameters:
    ///   - template: The template to use.
    ///   - rootURL: Project root, used when no pendingParentURL is set.
    ///   - fileService: Used to write the file.
    ///   - onSuccess: Called with the new FileItem if creation succeeds.
    ///   - onError: Called with an AppError if creation fails.
    func createFromTemplate(
        _ template: DocumentTemplate,
        rootURL: URL?,
        fileService: FileServiceProtocol,
        onSuccess: (FileItem) -> Void,
        onError: (AppError) -> Void
    ) {
        let targetDir = pendingParentURL ?? rootURL
        pendingParentURL = nil
        guard let targetDir else { return }

        let baseName = template.id == "blank" ? "untitled" : template.id
        let ext = template.fileExtension
        var url = targetDir.appendingPathComponent("\(baseName).\(ext)")
        var counter = 1
        while fileService.fileExists(at: url) {
            url = targetDir.appendingPathComponent("\(baseName) \(counter).\(ext)")
            counter += 1
        }
        do {
            try fileService.createFile(at: url, content: template.content)
            onSuccess(FileItem(url: url, isDirectory: false))
        } catch {
            onError(.fileCreate(url, underlying: error))
        }
    }

    /// Save the given content as a user template.
    func saveAs(name: String, content: String) throws {
        try store.save(name: name, content: content)
    }
}
