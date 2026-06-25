import Foundation

// MARK: - Read Document

struct ReadDocumentTool: AgentTool {
    let spec = AgentToolSpec(
        name: "read_document",
        description: "Read the full content of the currently open Markdown document."
    )

    func execute(arguments: [String: Any], context: AgentContext) async throws -> String {
        guard let content = await context.currentDocument else { throw AgentError.noDocument }
        let name = await context.currentDocumentName ?? "untitled"
        return "# Document: \(name)\n\n\(content)"
    }
}

// MARK: - Write Document

struct WriteDocumentTool: AgentTool {
    let spec = AgentToolSpec(
        name: "write_document",
        description: "Replace the entire document content with new Markdown text. Use only when rewriting the whole document or applying a complete transformation.",
        parameters: ToolParameterSchema(
            type: "object",
            properties: [
                "content": ToolPropertySchema(
                    type: "string",
                    description: "The new Markdown content to write to the document."
                )
            ],
            required: ["content"]
        )
    )

    func execute(arguments: [String: Any], context: AgentContext) async throws -> String {
        guard let content = arguments["content"] as? String else {
            throw AgentError.executionError("缺少 content 参数")
        }
        await context.writeDocument(content)
        return "✅ 文档已更新（\(content.count) 字符）"
    }
}

// MARK: - Insert At Cursor

struct InsertAtCursorTool: AgentTool {
    let spec = AgentToolSpec(
        name: "insert_at_cursor",
        description: "Insert text at the current cursor position in the editor. Prefer this over write_document when adding new content rather than replacing.",
        parameters: ToolParameterSchema(
            type: "object",
            properties: [
                "text": ToolPropertySchema(
                    type: "string",
                    description: "The Markdown text to insert at the cursor."
                )
            ],
            required: ["text"]
        )
    )

    func execute(arguments: [String: Any], context: AgentContext) async throws -> String {
        guard let text = arguments["text"] as? String else {
            throw AgentError.executionError("缺少 text 参数")
        }
        await context.insertIntoDocument(text)
        return "✅ 内容已插入（\(text.count) 字符）"
    }
}

// MARK: - Search Document

struct SearchDocumentTool: AgentTool {
    let spec = AgentToolSpec(
        name: "search_document",
        description: "Search for a keyword or phrase in the current document. Returns matching lines with line numbers.",
        parameters: ToolParameterSchema(
            type: "object",
            properties: [
                "query": ToolPropertySchema(
                    type: "string",
                    description: "The text to search for (case-insensitive)."
                )
            ],
            required: ["query"]
        )
    )

    func execute(arguments: [String: Any], context: AgentContext) async throws -> String {
        guard let query = arguments["query"] as? String else {
            throw AgentError.executionError("缺少 query 参数")
        }
        guard let content = await context.currentDocument else { throw AgentError.noDocument }

        let lines = content.components(separatedBy: "\n")
        let matches = lines.enumerated().compactMap { (idx, line) -> String? in
            line.localizedCaseInsensitiveContains(query) ? "L\(idx + 1): \(line)" : nil
        }
        if matches.isEmpty { return "未找到包含【\(query)】的内容" }
        return "找到 \(matches.count) 处匹配：\n\n" + matches.prefix(20).joined(separator: "\n")
    }
}

// MARK: - Read File

struct ReadFileTool: AgentTool {
    let spec = AgentToolSpec(
        name: "read_file",
        description: "Read the content of another file in the workspace by filename.",
        parameters: ToolParameterSchema(
            type: "object",
            properties: [
                "filename": ToolPropertySchema(
                    type: "string",
                    description: "The filename to read (e.g. README.md). Searches recursively in the workspace."
                )
            ],
            required: ["filename"]
        )
    )

    func execute(arguments: [String: Any], context: AgentContext) async throws -> String {
        guard let filename = arguments["filename"] as? String else {
            throw AgentError.executionError("缺少 filename 参数")
        }
        let files = await context.listWorkspaceFiles()
        guard let url = files.first(where: { $0.lastPathComponent == filename }) else {
            return "未找到文件：\(filename)"
        }
        let content = try await context.readFile(at: url)
        return "# \(filename)\n\n\(content)"
    }
}

// MARK: - List Files

struct ListFilesTool: AgentTool {
    let spec = AgentToolSpec(
        name: "list_files",
        description: "List all Markdown and text files in the current workspace.",
        parameters: ToolParameterSchema(
            type: "object",
            properties: [
                "extension": ToolPropertySchema(
                    type: "string",
                    description: "File extension filter, e.g. 'md', 'txt'. Leave empty for all files."
                )
            ],
            required: []
        )
    )

    func execute(arguments: [String: Any], context: AgentContext) async throws -> String {
        guard await context.workspaceURL != nil else { throw AgentError.noWorkspace }
        let ext = arguments["extension"] as? String ?? ""
        let exts = ext.isEmpty ? ["md", "txt", "markdown"] : [ext.lowercased()]
        let files = await context.listWorkspaceFiles(extensions: exts)
        if files.isEmpty { return "工作区没有找到文件" }
        let root = await context.workspaceURL?.path ?? ""
        let names = files.map { url -> String in
            let rel = url.path.hasPrefix(root) ? String(url.path.dropFirst(root.count + 1)) : url.lastPathComponent
            return "- \(rel)"
        }
        return "工作区文件（\(files.count) 个）：\n\n" + names.prefix(50).joined(separator: "\n")
    }
}

// MARK: - Registry

enum BuiltinAgentTools {
    static var all: [any AgentTool] {
        [
            ReadDocumentTool(),
            WriteDocumentTool(),
            InsertAtCursorTool(),
            SearchDocumentTool(),
            ReadFileTool(),
            ListFilesTool()
        ]
    }

    static func tool(named name: String) -> (any AgentTool)? {
        all.first { $0.spec.name == name }
    }
}
