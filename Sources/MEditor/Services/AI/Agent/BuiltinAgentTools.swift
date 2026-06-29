import Foundation

// MARK: - Tool Registry

/// 所有内建工具的注册表。
/// 工具实现分布在 Tools/ 子目录下，按功能域分组：
///   DocumentTools.swift  — 读写/搜索当前文档
///   WorkspaceTools.swift — 文件/目录操作
///   EditorTools.swift    — 编辑器交互（光标、打开文件）
enum BuiltinAgentTools {
    static let all: [any AgentTool] = [
        // Document
        ReadDocumentTool(),
        WriteDocumentTool(),
        PatchDocumentTool(),
        SearchDocumentTool(),
        // Workspace
        ListFilesTool(),
        ReadFileTool(),
        CreateFileTool(),
        WriteFileTool(),
        CreateDirectoryTool(),
        SearchWorkspaceTool(),
        // Editor
        InsertAtCursorTool(),
        OpenFileTool(),
        GetHTMLTemplateTool(),
    ]

    static func tool(named name: String) -> (any AgentTool)? {
        all.first { $0.spec.name == name }
    }
}
