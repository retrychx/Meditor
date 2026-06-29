import Foundation
import UniformTypeIdentifiers
#if os(macOS)
import AppKit

@MainActor
final class MacFilePickerService: FilePickerServiceProtocol {

    func pickFolder(message: String? = nil) async -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if let msg = message { panel.message = msg }
        return panel.runModal() == .OK ? panel.url : nil
    }

    func pickFile(title: String? = nil, allowedTypes: [UTType]) async -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if let t = title { panel.title = t }
        panel.allowedContentTypes = allowedTypes
        return panel.runModal() == .OK ? panel.url : nil
    }

    func pickFile(title: String? = nil, allowedExtensions: [String]) async -> URL? {
        let types = allowedExtensions.compactMap { UTType(filenameExtension: $0) }
        return await pickFile(title: title, allowedTypes: types)
    }
}
#endif
