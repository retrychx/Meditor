import Foundation

// 说明：以下四个 "*_document" 工具均支持可选的 `filename` 参数。
//   - 不传 filename → 作用于当前激活的编辑器文档（selectedTab）。
//   - 传 filename   → 直接作用于指定文件（文件名 / 工作区相对路径 / 绝对路径），
//                     无需先 open_file 激活 tab。

// MARK: - Read Document

struct ReadDocumentTool: AgentTool {
    let spec = AgentToolSpec(
        name: "read_document",
        description: "Read the full content of a document. Without 'filename', reads the currently open document. With 'filename', reads that specific file from the workspace (no need to open it first).",
        parameters: ToolParameterSchema(
            properties: [
                "filename": ToolPropertySchema(type: "string", description: "Optional. Filename, workspace-relative path, or absolute path. Omit to read the currently active document.")
            ],
            required: []
        )
    )

    func execute(arguments: [String: AnySendableValue], context: any AgentContextProtocol) async throws -> String {
        if let filename = arguments["filename"]?.stringValue, !filename.isEmpty {
            let resolved = await context.resolveFile(filename)
            guard case .found(let url) = resolved else {
                if let message = resolved.promptMessage(forQuery: filename) {
                    return message
                }
                return "未找到文件：\(filename)"
            }
            let content = try await context.readFile(at: url)
            return "# Document: \(url.lastPathComponent)\n\n\(content)"
        }
        guard let content = await context.currentDocument else { throw AgentError.noDocument }
        let name = await context.currentDocumentName ?? "untitled"
        return "# Document: \(name)\n\n\(content)"
    }
}

// MARK: - Write Document

struct WriteDocumentTool: AgentTool {
    let spec = AgentToolSpec(
        name: "write_document",
        description: "Replace the ENTIRE content of a document with new text. Only use for complete rewrites; for partial edits prefer patch_document. Without 'filename', rewrites the currently open document. With 'filename', writes that specific file (creating it if missing).",
        parameters: ToolParameterSchema(
            properties: [
                "content":  ToolPropertySchema(type: "string", description: "The new content to write."),
                "filename": ToolPropertySchema(type: "string", description: "Optional. Filename, workspace-relative path, or absolute path. Omit to rewrite the currently active document.")
            ],
            required: ["content"]
        )
    )

    func execute(arguments: [String: AnySendableValue], context: any AgentContextProtocol) async throws -> String {
        guard let content = arguments["content"]?.stringValue else {
            throw AgentError.executionError("缺少 content 参数")
        }
        if let filename = arguments["filename"]?.stringValue, !filename.isEmpty {
            // 已存在则用其绝对路径覆盖（避免裸文件名在根目录误建新文件）；否则按给定路径新建
            let resolved = await context.resolveFile(filename)
            if let message = resolved.promptMessage(forQuery: filename) {
                return message
            }
            // found 则用其绝对路径覆盖（避免裸文件名在根目录误建新文件）；notFound 则按给定路径新建
            let target: String
            if case .found(let foundURL) = resolved { target = foundURL.path } else { target = filename }
            do {
                let url = try await context.writeFile(name: target, content: content)
                return "[OK] 已写入文件：\(url.lastPathComponent)（\(content.count) 字符）"
            } catch {
                return "[!] 写入失败：\(error.localizedDescription)"
            }
        }
        do {
            try await context.writeDocument(content)
            return "[OK] 文档已全量更新（\(content.count) 字符）"
        } catch {
            return "[!] 写入失败：\(error.localizedDescription)"
        }
    }
}

// MARK: - Patch Document

struct PatchDocumentTool: AgentTool {
    let spec = AgentToolSpec(
        name: "patch_document",
        description: "Precisely replace a specific piece of text. Prefer this over write_document for partial edits. Without 'filename', patches the currently open document. With 'filename', patches that specific file directly (no need to open it first).",
        parameters: ToolParameterSchema(
            properties: [
                "find":        ToolPropertySchema(type: "string",  description: "The exact text to find (case-sensitive, literal match)."),
                "replace":     ToolPropertySchema(type: "string",  description: "The replacement text."),
                "replace_all": ToolPropertySchema(type: "boolean", description: "If true, replace all occurrences. Default: first match only."),
                "filename":    ToolPropertySchema(type: "string",  description: "Optional. Filename, workspace-relative path, or absolute path. Omit to patch the currently active document.")
            ],
            required: ["find", "replace"]
        )
    )

    func execute(arguments: [String: AnySendableValue], context: any AgentContextProtocol) async throws -> String {
        guard let find    = arguments["find"]?.stringValue,
              let replace = arguments["replace"]?.stringValue
        else { throw AgentError.executionError("缺少 find 或 replace 参数") }

        let replaceAll = arguments["replace_all"]?.boolValue ?? false

        if let filename = arguments["filename"]?.stringValue, !filename.isEmpty {
            do {
                let count = try await context.patchFile(name: filename, find: find, replace: replace, all: replaceAll)
                return "[OK] 已在 \(filename) 替换 \(count) 处"
            } catch let e as PatchNotFoundError {
                return e.errorDescription ?? "[!] 未找到匹配文本"
            } catch AgentContextError.fileNotFound(let name) {
                return "[!] 未找到文件：\(name)"
            }
        }

        do {
            let count = try await context.patchDocument(find: find, replace: replace, all: replaceAll)
            return "[OK] 已替换 \(count) 处"
        } catch let e as PatchNotFoundError {
            return e.errorDescription ?? "[!] 未找到匹配文本"
        }
    }
}

// MARK: - Search Document

struct SearchDocumentTool: AgentTool {
    let spec = AgentToolSpec(
        name: "search_document",
        description: "Search for a keyword or phrase in a document. Returns matching lines with line numbers. Without 'filename', searches the currently open document. With 'filename', searches that specific file.",
        parameters: ToolParameterSchema(
            properties: [
                "query":    ToolPropertySchema(type: "string", description: "The text to search for (case-insensitive)."),
                "filename": ToolPropertySchema(type: "string", description: "Optional. Filename, workspace-relative path, or absolute path. Omit to search the currently active document.")
            ],
            required: ["query"]
        )
    )

    func execute(arguments: [String: AnySendableValue], context: any AgentContextProtocol) async throws -> String {
        guard let query = arguments["query"]?.stringValue else {
            throw AgentError.executionError("缺少 query 参数")
        }

        let content: String
        if let filename = arguments["filename"]?.stringValue, !filename.isEmpty {
            let resolved = await context.resolveFile(filename)
            guard case .found(let url) = resolved else {
                if let message = resolved.promptMessage(forQuery: filename) {
                    return message
                }
                return "未找到文件：\(filename)"
            }
            // 用完整内容搜索（不走 readFile 的 64KB 截断），避免大文件后半段漏搜
            content = try await context.fileContentFull(at: url)
        } else {
            guard let current = await context.currentDocument else { throw AgentError.noDocument }
            content = current
        }

        let lines = content.components(separatedBy: "\n")
        let matches = lines.enumerated().compactMap { (idx, line) -> String? in
            line.localizedCaseInsensitiveContains(query) ? "L\(idx + 1): \(line)" : nil
        }
        if matches.isEmpty { return "未找到包含【\(query)】的内容" }
        return "找到 \(matches.count) 处匹配：\n\n" + matches.prefix(20).joined(separator: "\n")
    }
}
