import Foundation

// 说明：以下四个 "*_document" 工具均支持可选的 `filename` 参数。
//   - 不传 filename → 作用于当前激活的编辑器文档（selectedTab）。
//   - 传 filename   → 直接作用于指定文件（文件名 / 工作区相对路径 / 绝对路径），
//                     无需先 open_file 激活 tab。

// MARK: - Read Document

struct ReadDocumentTool: AgentTool {
    /// 与磁盘读取路径（AgentFileRepository）一致的截断上限。
    /// 激活 tab 此前走 tab.content 全文返回——大文档一次读穿，且结果永久留在
    /// agentHistory 里逐轮重发（成本审计 8.1）。改为：默认截断 + 行区间读取。
    private static let maxChars = 64 * 1024

    let spec = AgentToolSpec(
        name: "read_document",
        description: "Read the content of a document. Without 'filename', reads the currently open document. With 'filename', reads that specific file from the workspace (no need to open it first). Long documents are truncated to 64K characters — use 'start_line'/'end_line' to read a specific range instead of re-reading the whole document.",
        parameters: ToolParameterSchema(
            properties: [
                "filename":   ToolPropertySchema(type: "string",  description: "Optional. Filename, workspace-relative path, or absolute path. Omit to read the currently active document."),
                "start_line": ToolPropertySchema(type: "integer", description: "Optional. 1-based line to start reading from. Use with end_line to read a specific range."),
                "end_line":   ToolPropertySchema(type: "integer", description: "Optional. 1-based inclusive line to stop at. Use with start_line to read a specific range.")
            ],
            required: []
        )
    )

    func execute(arguments: [String: AnySendableValue], context: any AgentContextProtocol) async throws -> String {
        let startLine = arguments["start_line"]?.intValue
        let endLine = arguments["end_line"]?.intValue

        let name: String
        let content: String
        if let filename = arguments["filename"]?.stringValue, !filename.isEmpty {
            let resolved = await context.resolveFile(filename)
            guard case .found(let url) = resolved else {
                if let message = resolved.promptMessage(forQuery: filename) {
                    return message
                }
                return "未找到文件：\(filename)"
            }
            name = url.lastPathComponent
            // 行区间读取用完整内容（不走 readFile 的 64KB 截断，避免区间落在截断点外）
            content = (startLine != nil || endLine != nil)
                ? (try await context.fileContentFull(at: url))
                : (try await context.readFile(at: url))
        } else {
            guard let current = await context.currentDocument else { throw AgentError.noDocument }
            name = await context.currentDocumentName ?? "untitled"
            content = current
        }

        if startLine != nil || endLine != nil {
            return Self.rangeSlice(content, name: name, start: startLine, end: endLine)
        }
        return Self.truncated(content, name: name)
    }

    /// 行区间切片（1-based、闭区间），附带总行数提示。
    static func rangeSlice(_ content: String, name: String, start: Int?, end: Int?) -> String {
        let lines = content.components(separatedBy: "\n")
        let from = max(1, start ?? 1)
        let to = min(lines.count, end ?? lines.count)
        guard from <= to else {
            return "[!] 行区间无效：L\(from)–L\(to)（全文共 \(lines.count) 行）"
        }
        let body = lines[(from - 1)...(to - 1)].joined(separator: "\n")
        return "# Document: \(name)（第 \(from)–\(to) 行，共 \(lines.count) 行）\n\n\(body)"
    }

    /// 超限时截断并给出区间读取指引（比静默截断更可操作）。
    static func truncated(_ content: String, name: String) -> String {
        guard content.count > maxChars else {
            return "# Document: \(name)\n\n\(content)"
        }
        return "# Document: \(name)（已截断至前 \(maxChars) 字符，可用 start_line/end_line 按行区间继续读取）\n\n"
            + content.prefix(maxChars)
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
