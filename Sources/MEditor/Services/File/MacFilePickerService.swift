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
        panel.showsHiddenFiles = true
        if let msg = message { panel.message = msg }
        return panel.runModal() == .OK ? panel.url : nil
    }

    func pickFile(title: String? = nil, allowedTypes: [UTType]) async -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        if let t = title { panel.title = t }
        panel.allowedContentTypes = allowedTypes
        return panel.runModal() == .OK ? panel.url : nil
    }

    func pickFile(title: String? = nil, allowedExtensions: [String]) async -> URL? {
        let types = allowedExtensions.compactMap { UTType(filenameExtension: $0) }
        return await pickFile(title: title, allowedTypes: types)
    }

    func pickFileOrFolder(title: String? = nil, allowedExtensions: [String]) async -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true       // 允许选 skill 文件夹 / 插件目录
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true           // 允许进入 .claude 等隐藏目录
        if let t = title { panel.title = t }
        let types = allowedExtensions.compactMap { UTType(filenameExtension: $0) }
        if !types.isEmpty { panel.allowedContentTypes = types }  // 仅过滤"文件"类型；目录始终可选
        return panel.runModal() == .OK ? panel.url : nil
    }
}
#endif
