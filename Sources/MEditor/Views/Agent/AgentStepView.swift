import SwiftUI

// MARK: - ShakeEffect

/// 轻微水平抗动，用于工具调用失败时的视觉反馈。
struct ShakeEffect: GeometryEffect {
    var amount: CGFloat = 4
    var shakesPerUnit = 3
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        .init(CGAffineTransform(
            translationX: amount * sin(animatableData * .pi * CGFloat(shakesPerUnit)), y: 0
        ))
    }
}

// MARK: - AgentStepView

/// 展示单个执行步骤（thinking / tool call / done），带入场、状态过渡、错误抗动动画。
struct AgentStepView: View {
    let step: AgentRunnerStep
    var compact: Bool = false   // 紧凑单行模式（AI 助手内联使用）
    @Environment(AppState.self) private var state

    // MARK: - Animation state
    @State private var pulsing        = false   // thinking 呼吸灯
    @State private var resultShown    = false   // 工具结果文字展开
    @State private var resultExpanded = false   // 工具结果内容展开（多行/长文）
    @State private var errorShake: CGFloat = 0  // 错误抗动进度

    var body: some View {
        Group {
            if compact {
                compactRow
            } else {
                switch step {
                case .thinking(let label, _):
                    thinkingView(label: label)
                case .toolCall(_, let name, let args):
                    toolCallView(name: name, args: args)
                case .toolCallDone(_, let name, _, let result, let isError):
                    toolCallView(name: name, args: "", result: result, isError: isError)
                }
            }
        }
        .modifier(ShakeEffect(animatableData: errorShake))
        // 工具状态变化（toolCall → toolCallDone）时触发动画
        .onChange(of: step.isDone) { _, isDone in
            guard isDone else { return }
            withAnimation(DS.Motion.spring) { resultShown = true }
            if step.isError {
                withAnimation(.easeInOut(duration: 0.35)) { errorShake = 1 }
            }
        }
        // 首次展示时如果已是 done（历史步骤回放）
        .onAppear {
            if step.isDone { resultShown = true }
        }
    }

    // MARK: - Compact single-line row

    /// 紧凑单行：状态图标 + 操作简述，用于 AI 助手内联的工具过程列表。
    @ViewBuilder
    private var compactRow: some View {
        switch step {
        case .thinking(let label, _):
            HStack(spacing: 7) {
                ProgressView().controlSize(.mini).scaleEffect(0.8)
                    .frame(width: 13, height: 13)
                Text(label)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .opacity(pulsing ? 0.6 : 1.0)
            .onAppear { withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { pulsing = true } }
            .onDisappear { pulsing = false }
        case .toolCall(_, let name, let args):
            compactToolRow(text: toolLabel(name: name, args: args).text, done: false, isError: false)
        case .toolCallDone(_, let name, let args, _, let isError):
            compactToolRow(text: toolLabel(name: name, args: args).text, done: true, isError: isError)
        }
    }

    private func compactToolRow(text: String, done: Bool, isError: Bool) -> some View {
        HStack(spacing: 7) {
            Group {
                if !done {
                    ProgressView().controlSize(.mini).scaleEffect(0.8)
                } else {
                    Image(systemName: isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 11.5))
                        .foregroundStyle(isError ? Color.red : Color.green)
                }
            }
            .frame(width: 13, height: 13)
            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(.primary.opacity(0.85))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Thinking

    @ViewBuilder
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
        // 呼吸灯：整行 opacity 0.55↔1.0 循环
        .opacity(pulsing ? 0.55 : 1.0)
        .onAppear { withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { pulsing = true } }
        .onDisappear { pulsing = false }
    }

    // MARK: - Tool Call

    /// 从 JSON args 字符串中提取指定 key 的字符串值。
    /// 使用 JSONSerialization 解析，正确处理嵌套对象、数组、转义字符等边界情况。
    private func argValue(_ key: String, from args: String) -> String? {
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
        case "run_command":
            let cmd = argValue("command", from: args) ?? ""
            if cmd.isEmpty { return ("terminal", "执行命令", .orange) }
            let short = cmd.count > 36 ? String(cmd.prefix(36)) + "…" : cmd
            return ("terminal", "执行命令 · \(short)", .orange)
        default:
            return ("gearshape.fill", name, .orange)
        }
    }

    /// 从结果字符串前缀推断 SF Symbol 图标名（nil = 不显示额外图标）
    private func resultIcon(from raw: String) -> (name: String, color: Color)? {
        if raw.hasPrefix("[OK] ")  { return ("checkmark.circle",          .green)  }
        if raw.hasPrefix("[!] ")   { return ("exclamationmark.triangle",   .orange) }
        if raw.hasPrefix("[X] ")   { return ("xmark.circle",               .red)    }
        return nil
    }

    /// 去掉 [OK]/[!]/[X] 前缀并 trim，返回完整内容（不截断）。
    private func stripResultPrefix(_ raw: String) -> String {
        var s = raw
        for prefix in ["[OK] ", "[!] ", "[X] "] {
            if s.hasPrefix(prefix) { s = String(s.dropFirst(prefix.count)); break }
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 工具结果摘要：去掉文字前缀，截断长文本
    private func resultSummary(_ raw: String) -> String {
        let trimmed = stripResultPrefix(raw)
        let firstLine = trimmed.components(separatedBy: "\n").first ?? trimmed
        return firstLine.count > 80 ? String(firstLine.prefix(80)) + "…" : firstLine
    }

    /// `args` 在 done=true 时为空，利用 `resultShown` 控制结果文字的展开动画。
    @ViewBuilder
    private func toolCallView(
        name: String,
        args: String,
        result: String? = nil,
        isError: Bool = false
    ) -> some View {
        let done   = step.isDone
        let label  = toolLabel(name: name, args: args)
        let accent: Color = done ? (isError ? .red : label.accent) : label.accent

        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                // 图标：调用中 → 成功/失败，颜色平滑过渡
                Image(systemName: done
                      ? (isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                      : label.icon)
                    .font(.system(size: 11.5))
                    .foregroundStyle(accent)
                    .animation(DS.Motion.standard, value: done)

                Text(label.text)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if !done {
                    ProgressView()
                        .controlSize(.small)
                        .tint(accent)
                        .transition(.opacity)
                }
                Spacer(minLength: 0)
            }

            // 结果行：状态变为 done 后展开
            if let result, !result.isEmpty, resultShown {
                let stripped    = stripResultPrefix(result)
                let icon        = resultIcon(from: result)
                let needsExpand = result.contains("\n") || stripped.count > 80
                let summary     = resultSummary(result)
                HStack(alignment: .top, spacing: 4) {
                    if let icon {
                        Image(systemName: icon.name)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(icon.color.opacity(0.85))
                            .padding(.top, 1)
                    }
                    if resultExpanded {
                        ScrollView(.vertical) {
                            Text(stripped)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 200)
                    } else {
                        Text(summary)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    if needsExpand {
                        Spacer(minLength: 0)
                        Button {
                            withAnimation(DS.Motion.spring) { resultExpanded.toggle() }
                        } label: {
                            Image(systemName: resultExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            accent.opacity(0.07),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .animation(DS.Motion.standard, value: accent)   // 背景颜色平滑过渡
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(accent.opacity(0.22), lineWidth: 1)
                .animation(DS.Motion.standard, value: accent)
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

    @State private var finalTextExpanded = false
    @State private var copyDone = false

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
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(runner.steps) { step in
                            AgentStepView(step: step)
                                .environment(state)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .bottom).combined(with: .opacity),
                                    removal:   .opacity
                                ))
                        }
                        .animation(DS.Motion.spring, value: runner.steps.count)

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

                        // 滚动锤点
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
                // finalText 展示区
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "text.bubble")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text("回复")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(runner.finalText, forType: .string)
                            copyDone = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                copyDone = false
                            }
                        } label: {
                            Image(systemName: copyDone ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    Text(runner.finalText)
                        .font(.system(size: 12.5))
                        .lineLimit(finalTextExpanded ? nil : 4)
                        .fixedSize(horizontal: false, vertical: true)
                    let needsExpand = runner.finalText.components(separatedBy: "\n").count > 4
                        || runner.finalText.count > 200
                    if needsExpand {
                        Button {
                            withAnimation(DS.Motion.spring) { finalTextExpanded.toggle() }
                        } label: {
                            Text(finalTextExpanded ? "收起" : "展开")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.appAccent)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

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