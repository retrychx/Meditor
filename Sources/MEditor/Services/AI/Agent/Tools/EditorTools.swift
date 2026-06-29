import Foundation

// MARK: - Insert At Cursor

struct InsertAtCursorTool: AgentTool {
    let spec = AgentToolSpec(
        name: "insert_at_cursor",
        description: "Insert text at the current cursor position in the editor. Prefer this over write_document when adding new content rather than replacing.",
        parameters: ToolParameterSchema(
            properties: [
                "text": ToolPropertySchema(type: "string", description: "The Markdown text to insert at the cursor.")
            ],
            required: ["text"]
        )
    )

    func execute(arguments: [String: AnySendableValue], context: any AgentContextProtocol) async throws -> String {
        guard let text = arguments["text"]?.stringValue else {
            throw AgentError.executionError("缺少 text 参数")
        }
        await context.insertIntoDocument(text)
        return "✅ 内容已插入（\(text.count) 字符）"
    }
}

// MARK: - Open File

struct OpenFileTool: AgentTool {
    let spec = AgentToolSpec(
        name: "open_file",
        description: "Open a file in the editor AND return its full content. Accepts a filename (e.g. 'README.md'), a workspace-relative path (e.g. 'docs/intro.md'), or an absolute path. The file must exist.",
        parameters: ToolParameterSchema(
            properties: [
                "filename": ToolPropertySchema(type: "string", description: "Filename, relative path from workspace root, or absolute path of the file to open.")
            ],
            required: ["filename"]
        )
    )

    func execute(arguments: [String: AnySendableValue], context: any AgentContextProtocol) async throws -> String {
        guard let filename = arguments["filename"]?.stringValue else {
            throw AgentError.executionError("缺少 filename 参数")
        }
        let opened = await context.openFile(named: filename)
        guard opened else { return "⚠️ 未找到文件：\(filename)" }
        // 编辑器内容是异步加载的，open 之后 selectedTab.content 仍可能为空，
        // 因此这里直接从磁盘读回内容一并返回，避免 agent 误以为"已看到内容"而产生幻觉。
        if let url = await context.resolveExistingFile(filename),
           let content = try? await context.readFile(at: url) {
            return "✅ 已在编辑器中打开：\(filename)\n\n# \(filename)\n\n\(content)"
        }
        return "✅ 已在编辑器中打开：\(filename)"
    }
}
