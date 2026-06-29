import SwiftUI

/// Displays a single agent execution step (thinking / tool call / result).
struct AgentStepView: View {
    let step: AgentRunnerStep
    @Environment(AppState.self) private var state

    var body: some View {
        Group {
            switch step {
            case .thinking(let label, _):
                thinkingView(label: label)
            case .toolCall(_, let name, let args):
                toolCallView(name: name, args: args, done: false, isError: false, result: nil)
            case .toolCallDone(_, let name, _, let result, let isError):
                toolCallView(name: name, args: "", done: true, isError: isError, result: result)
            }
        }
    }

    // MARK: - Thinking

    private func thinkingView(label: String) -> some View {
        HStack(spacing: 8) {
            ProgressView().scaleEffect(0.7).controlSize(.small)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Tool Call

    /// 从 JSON args 字符串中提取指定 key 的字符串值（简单正则，不依赖 Codable）
    private func argValue(_ key: String, from args: String) -> String? {
        // 从 JSON args 字符串提取 "key": "value"，逐字符解析，不依赖 NSRegularExpression
        guard let keyStart = args.range(of: "\"" + key + "\"") else { return nil }
        var rest = args[keyStart.upperBound...]
        // 跳过 : 和空格，找到第一个 "
        while let first = rest.first, first != "\"" { rest = rest.dropFirst() }
        guard rest.hasPrefix("\"") else { return nil }
        rest = rest.dropFirst() // 去掉开头引号
        var value = ""
        var escaped = false
        for ch in rest {
            if escaped { escaped = false; value.append(ch); continue }
            if ch == "\\" { escaped = true; continue }
            if ch == "\"" { break }
            value.append(ch)
        }
        return value.replacingOccurrences(of: "\\n", with: " ")
    }

    /// 将工具名 + 参数转成人类可读的操作摘要
    private func toolLabel(name: String, args: String) -> (icon: String, text: String, accent: Color) {
        switch name {
        case "create_file":
            let file = argValue("filename", from: args) ?? ""
            return ("doc.badge.plus", file.isEmpty ? "创建文件" : "创建文件 · \(URL(fileURLWithPath: file).lastPathComponent)", .blue)
        case "write_file":
            let file = argValue("filename", from: args) ?? ""
            let body = argValue("content", from: args) ?? ""
            let size = body.isEmpty ? "" : " (\(body.count) 字)"
            return ("square.and.pencil", file.isEmpty ? "写入文件\(size)" : "写入 \(URL(fileURLWithPath: file).lastPathComponent)\(size)", .indigo)
        case "create_directory":
            let path = argValue("path", from: args) ?? ""
            return ("folder.badge.plus", path.isEmpty ? "创建目录" : "创建目录 · \(path)", .purple)
        case "write_document":
            let body = argValue("content", from: args) ?? ""
            let size = body.isEmpty ? "" : " (\(body.count) 字)"
            return ("pencil.and.list.clipboard", "更新当前文档\(size)", .orange)
        case "patch_document":
            let find = argValue("find", from: args) ?? ""
            let preview = find.isEmpty ? "" : " · 「\(String(find.prefix(20)))\(find.count > 20 ? "…" : "")」"
            return ("scissors", "精准修改文档\(preview)", .orange)
        case "read_document":
            return ("doc.text.magnifyingglass", "读取当前文档", .gray)
        case "read_file":
            let file = argValue("filename", from: args) ?? ""
            return ("doc.text.magnifyingglass", file.isEmpty ? "读取文件" : "读取 · \(file)", .gray)
        case "open_file":
            let file = argValue("filename", from: args) ?? ""
            return ("arrow.up.right.square", file.isEmpty ? "打开文件" : "打开 · \(file)", .cyan)
        case "insert_at_cursor":
            let body = argValue("text", from: args) ?? ""
            let size = body.isEmpty ? "" : " (\(body.count) 字)"
            return ("text.insert", "插入内容\(size)", .teal)
        case "list_files":
            return ("list.bullet", "列出工作区文件", .gray)
        case "search_workspace":
            let q = argValue("query", from: args) ?? ""
            return ("magnifyingglass", q.isEmpty ? "搜索工作区" : "搜索「\(q)」", .gray)
        case "search_document":
            let q = argValue("query", from: args) ?? ""
            return ("magnifyingglass", q.isEmpty ? "搜索文档" : "文档内搜索「\(q)」", .gray)
        default:
            return ("gearshape.fill", name, .orange)
        }
    }

    /// 工具结果摘要：去掉 ✅/⚠️ 前缀，截断长文本
    private func resultSummary(_ raw: String) -> String {
        var s = raw
        // 去掉表情前缀
        for prefix in ["✅ ", "⚠️ ", "❌ "] {
            if s.hasPrefix(prefix) { s = String(s.dropFirst(prefix.count)) }
        }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        // 多行内容只展示第一行
        let firstLine = trimmed.components(separatedBy: "\n").first ?? trimmed
        return firstLine.count > 80 ? String(firstLine.prefix(80)) + "…" : firstLine
    }

    private func toolCallView(name: String, args: String, done: Bool, isError: Bool, result: String?) -> some View {
        let label = toolLabel(name: name, args: args)
        let accent: Color = done ? (isError ? .red : label.accent) : label.accent

        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: done
                      ? (isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                      : label.icon)
                    .font(.system(size: 11.5))
                    .foregroundStyle(accent)
                Text(label.text)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if !done {
                    ProgressView().scaleEffect(0.6).controlSize(.mini)
                }
                Spacer(minLength: 0)
            }

            if let result, !result.isEmpty {
                let summary = resultSummary(result)
                if !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            accent.opacity(0.07),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(accent.opacity(0.22), lineWidth: 1)
        )
    }

    // MARK: - Final Text

}

// MARK: - Agent Result Panel

/// Full panel showing agent steps + final result + apply button.
struct AgentResultPanel: View {
    @Environment(AppState.self) private var state
    @Bindable var runner: AgentRunner
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Label("Agent 执行", systemImage: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if runner.isRunning {
                    Button {
                        runner.cancel()
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .foregroundStyle(Color.red.opacity(0.8))
                            .font(.system(size: 15))
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 15))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // Steps
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(runner.steps) { step in
                            AgentStepView(step: step)
                                .environment(state)
                        }

                        if let err = runner.error {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.red)
                                    .font(.system(size: 11))
                                Text(err)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.red)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        }

                        // 滚动锚点
                        Color.clear.frame(height: 1).id("agentBottom")
                    }
                    .padding(12)
                }
                .frame(maxHeight: 380)
                .onChange(of: runner.steps.count) { _, _ in
                    DispatchQueue.main.async {
                        withAnimation(DS.Motion.standard) {
                            proxy.scrollTo("agentBottom", anchor: .bottom)
                        }
                    }
                }
            }

            if !runner.isRunning && !runner.finalText.isEmpty {
                Divider()
                HStack {
                    Spacer()
                    Text("Agent 已完成")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Button("完成") { onDismiss() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(Color.appAccent)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 8)
    }
}