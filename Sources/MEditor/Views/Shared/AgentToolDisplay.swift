import Foundation

// MARK: - AgentToolDisplay（macOS / iOS 共享）

/// 工具名 + JSON 参数 → 人类可读的展示信息（图标 / 摘要文案 / 强调色 token）。
/// 纯字符串逻辑，不依赖任何平台 UI API；颜色与排版由各端视图层自行决定
/// （macOS AgentStepView 用 accent 着色卡片，iOS AgentStepsView 只用 icon/text）。
struct AgentToolDisplayInfo: Sendable {
    /// SF Symbol 名
    let icon: String
    /// 人类可读的操作摘要
    let text: String
    /// 平台中性的强调色 token
    let accent: AgentToolAccent
}

/// 平台中性的强调色 token，各端视图层映射到自己的 Color。
enum AgentToolAccent: String, Sendable {
    case blue, indigo, purple, orange, gray, cyan, teal
}

enum AgentToolDisplay {

    /// 将工具名 + 参数转成人类可读的操作摘要
    /// 文案走全局 L() 查表（macOS / iOS 两个 target 都编译 Localization.swift，可直接调用）
    static func info(name: String, args: String) -> AgentToolDisplayInfo {
        switch name {
        case "create_file":
            let file = argValue("filename", from: args) ?? ""
            return .init("doc.badge.plus", file.isEmpty ? L("ai.tool.createFile") : L("ai.tool.createFileNamed", URL(fileURLWithPath: file).lastPathComponent), .blue)
        case "write_file":
            let file = argValue("filename", from: args) ?? ""
            let body = argValue("content", from: args) ?? ""
            let size = body.isEmpty ? "" : L("ai.tool.sizeSuffix", body.count)
            return .init("square.and.pencil", file.isEmpty ? L("ai.tool.writeFile", size) : L("ai.tool.writeFileNamed", URL(fileURLWithPath: file).lastPathComponent, size), .indigo)
        case "create_directory":
            let path = argValue("path", from: args) ?? ""
            return .init("folder.badge.plus", path.isEmpty ? L("ai.tool.createDir") : L("ai.tool.createDirNamed", path), .purple)
        case "write_document":
            let body = argValue("content", from: args) ?? ""
            let size = body.isEmpty ? "" : L("ai.tool.sizeSuffix", body.count)
            return .init("pencil.and.list.clipboard", L("ai.tool.updateDocument", size), .orange)
        case "patch_document":
            let find = argValue("find", from: args) ?? ""
            let preview = find.isEmpty ? "" : L("ai.tool.patchPreview", String(find.prefix(20)) + (find.count > 20 ? "…" : ""))
            return .init("scissors", L("ai.tool.patchDocument", preview), .orange)
        case "read_document":
            return .init("doc.text.magnifyingglass", L("ai.tool.readDocument"), .gray)
        case "read_file":
            let file = argValue("filename", from: args) ?? ""
            return .init("doc.text.magnifyingglass", file.isEmpty ? L("ai.tool.readFile") : L("ai.tool.readFileNamed", file), .gray)
        case "open_file":
            let file = argValue("filename", from: args) ?? ""
            return .init("arrow.up.right.square", file.isEmpty ? L("ai.tool.openFile") : L("ai.tool.openFileNamed", file), .cyan)
        case "insert_at_cursor":
            let body = argValue("text", from: args) ?? ""
            let size = body.isEmpty ? "" : L("ai.tool.sizeSuffix", body.count)
            return .init("text.insert", L("ai.tool.insertAtCursor", size), .teal)
        case "list_files":
            return .init("list.bullet", L("ai.tool.listFiles"), .gray)
        case "search_workspace":
            let q = argValue("query", from: args) ?? ""
            return .init("magnifyingglass", q.isEmpty ? L("ai.tool.searchWorkspace") : L("ai.tool.searchWorkspaceQuery", q), .gray)
        case "search_document":
            let q = argValue("query", from: args) ?? ""
            return .init("magnifyingglass", q.isEmpty ? L("ai.tool.searchDocument") : L("ai.tool.searchDocumentQuery", q), .gray)
        case "run_command":
            let cmd = argValue("command", from: args) ?? ""
            if cmd.isEmpty { return .init("terminal", L("ai.tool.runCommand"), .orange) }
            let short = cmd.count > 36 ? String(cmd.prefix(36)) + "…" : cmd
            return .init("terminal", L("ai.tool.runCommandNamed", short), .orange)
        default:
            return .init("gearshape.fill", name, .orange)
        }
    }

    /// 从 JSON args 字符串中提取指定 key 的字符串值。
    /// 使用 JSONSerialization 解析，正确处理嵌套对象、数组、转义字符等边界情况。
    static func argValue(_ key: String, from args: String) -> String? {
        guard let data = args.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        // 字符串值直接返回；非字符串值序列化为紧凑 JSON 字符串
        if let str = obj[key] as? String { return str }
        if let val = obj[key] {
            let serialized = (try? JSONSerialization.data(withJSONObject: val))
                .flatMap { String(data: $0, encoding: .utf8) }
            return serialized
        }
        return nil
    }
}

private extension AgentToolDisplayInfo {
    init(_ icon: String, _ text: String, _ accent: AgentToolAccent) {
        self.icon = icon
        self.text = text
        self.accent = accent
    }
}
