import SwiftUI

/// Agent 工具步骤条：聊天回复上方的过程可视化（读/改/搜一目了然）。
/// 运行中由 ChatModel.runner.steps 驱动（spinner），结束后用消息里的快照回放（勾/叉）。
/// 文案与桌面端 AgentStepView 保持一致。
struct AgentStepsView: View {
    let steps: [AgentRunnerStep]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(steps) { step in
                row(step)
            }
        }
    }

    @ViewBuilder
    private func row(_ step: AgentRunnerStep) -> some View {
        switch step {
        case .thinking(let label, _):
            HStack(spacing: 7) {
                ProgressView().controlSize(.mini)
                Text(label)
                    .font(.footnote)
                    .foregroundStyle(PaperTheme.inkSecondary)
            }
        case .toolCall(_, let name, let args):
            let (icon, text) = Self.toolLabel(name: name, args: args)
            HStack(spacing: 7) {
                ProgressView().controlSize(.mini)
                    .frame(width: 12, height: 12)
                Label(text, systemImage: icon)
                    .font(.footnote)
                    .foregroundStyle(PaperTheme.inkSecondary)
            }
        case .toolCallDone(_, let name, let args, _, let isError):
            let (icon, text) = Self.toolLabel(name: name, args: args)
            HStack(spacing: 7) {
                Image(systemName: isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(isError ? .red : .green)
                Label(text, systemImage: icon)
                    .font(.footnote)
                    .foregroundStyle(isError ? .red : PaperTheme.inkSecondary)
            }
        }
    }

    // MARK: - 工具名 → 人类可读摘要（与桌面端 AgentStepView 同步）

    private static func toolLabel(name: String, args: String) -> (icon: String, text: String) {
        switch name {
        case "create_file":
            let file = argValue("filename", from: args) ?? ""
            return ("doc.badge.plus", file.isEmpty ? "创建文件" : "创建文件 · \(URL(fileURLWithPath: file).lastPathComponent)")
        case "write_file":
            let file = argValue("filename", from: args) ?? ""
            let body = argValue("content", from: args) ?? ""
            let size = body.isEmpty ? "" : " (\(body.count) 字)"
            return ("square.and.pencil", file.isEmpty ? "写入文件\(size)" : "写入 \(URL(fileURLWithPath: file).lastPathComponent)\(size)")
        case "create_directory":
            let path = argValue("path", from: args) ?? ""
            return ("folder.badge.plus", path.isEmpty ? "创建目录" : "创建目录 · \(path)")
        case "write_document":
            let body = argValue("content", from: args) ?? ""
            let size = body.isEmpty ? "" : " (\(body.count) 字)"
            return ("pencil.and.list.clipboard", "更新当前文档\(size)")
        case "patch_document":
            let find = argValue("find", from: args) ?? ""
            let preview = find.isEmpty ? "" : " · 「\(String(find.prefix(20)))\(find.count > 20 ? "…" : "")」"
            return ("scissors", "精准修改文档\(preview)")
        case "read_document":
            return ("doc.text.magnifyingglass", "读取当前文档")
        case "read_file":
            let file = argValue("filename", from: args) ?? ""
            return ("doc.text.magnifyingglass", file.isEmpty ? "读取文件" : "读取 · \(file)")
        case "open_file":
            let file = argValue("filename", from: args) ?? ""
            return ("arrow.up.right.square", file.isEmpty ? "打开文件" : "打开 · \(file)")
        case "insert_at_cursor":
            let body = argValue("text", from: args) ?? ""
            let size = body.isEmpty ? "" : " (\(body.count) 字)"
            return ("text.insert", "插入内容\(size)")
        case "list_files":
            return ("list.bullet", "列出工作区文件")
        case "search_workspace":
            let q = argValue("query", from: args) ?? ""
            return ("magnifyingglass", q.isEmpty ? "搜索工作区" : "搜索「\(q)」")
        case "search_document":
            let q = argValue("query", from: args) ?? ""
            return ("magnifyingglass", q.isEmpty ? "搜索文档" : "文档内搜索「\(q)」")
        default:
            return ("gearshape.fill", name)
        }
    }

    private static func argValue(_ key: String, from args: String) -> String? {
        guard let data = args.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = dict[key] else { return nil }
        return (value as? String) ?? String(describing: value)
    }
}
