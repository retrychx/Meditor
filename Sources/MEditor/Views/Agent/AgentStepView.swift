import SwiftUI

/// Displays a single agent execution step (thinking / tool call / result / text).
struct AgentStepView: View {
    let step: AgentRunnerStep
    @Environment(AppState.self) private var state

    var body: some View {
        Group {
            switch step {
            case .thinking(let label):
                thinkingView(label: label)
            case .toolCall(_, let name, let args):
                toolCallView(name: name, args: args, done: false, isError: false, result: nil)
            case .toolCallDone(_, let name, _, let result, let isError):
                toolCallView(name: name, args: "", done: true, isError: isError, result: result)
            case .text(let text):
                textView(text)
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

    private func toolCallView(name: String, args: String, done: Bool, isError: Bool, result: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: done
                      ? (isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                      : "gearshape.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(done
                        ? (isError ? Color.red : Color.green)
                        : Color.orange)
                Text("调用工具：\(name)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)

                if !done {
                    ProgressView().scaleEffect(0.6).controlSize(.mini)
                }
            }

            if let result, !result.isEmpty {
                Text(result.count > 200 ? String(result.prefix(200)) + "…" : result)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            (done ? (isError ? Color.red : Color.green) : Color.orange).opacity(0.07),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder((done ? (isError ? Color.red : Color.green) : Color.orange).opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Final Text

    private func textView(_ text: String) -> some View {
        MarkdownText(
            markdown: text,
            textColor: state.themeStore.current.craftPrimary,
            secondaryColor: state.themeStore.current.craftSecondary,
            codeBackground: state.themeStore.current.isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.045),
            accent: Color.appAccent
        )
            .padding(.horizontal, 4)
    }
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
                }
                .padding(12)
            }
            .frame(maxHeight: 380)

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
