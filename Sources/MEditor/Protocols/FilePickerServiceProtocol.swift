import Foundation
import UniformTypeIdentifiers

/// 跨平台文件/目录选择服务协议。
/// macOS 实现：MacFilePickerService（NSOpenPanel）
/// iOS 实现（将来）：UIDocumentPickerViewController
protocol FilePickerServiceProtocol {
    /// 选择一个目录，返回 nil 表示取消
    func pickFolder(message: String?) async -> URL?
    /// 选择单个文件
    func pickFile(title: String?, allowedTypes: [UTType]) async -> URL?
    /// 选择单个文件（扩展名列表，方便调用方）
    func pickFile(title: String?, allowedExtensions: [String]) async -> URL?
    /// 选择文件或文件夹（用于 skill：可选 SKILL.md 本身或其所在文件夹 / 插件目录）
    func pickFileOrFolder(title: String?, allowedExtensions: [String]) async -> URL?
}
