import SwiftUI

/// Sheet that streams an AI edit of a text selection, shows a before/after
/// diff, and lets the user accept (replace selection) or discard.
struct InlineEditSheet: View {
    @Environment(AppState.self) private var state
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    let originalText: String
    let action: InlineEditAction

    @State private var result     = ""
    @State private var isRunning  = false
    @State private var isDone     = false
    @State private var errorMsg: String? = nil
    @State private var streamTask: Task<Void, Never>? = nil

    private let agent = InlineEditAgent()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(spacing: 12) {
                    originalSection
                    if isRunning || isDone {
                        resultSection
                    }
                    if let err = errorMsg {
                        errorSection(err)
                    }
                }
                .padding(16)
            }
            Divider()
            bottomBar
        }
        .frame(minWidth: 480, minHeight: 360)
        .onAppear { startProcessing() }
        .onDisappear { streamTask?.cancel() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: action.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.purple)
            Text(statusTitle)
                .font(.system(size: 14, weight: .semibold))
            if isRunning {
                ProgressView().scaleEffect(0.7)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .background(Circle().fill(.quaternary))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var statusTitle: String {
        if isRunning { return "\(action.rawValue)中…" }
        if isDone    { return "\(action.rawValue)完成" }
        return action.rawValue
    }

    // MARK: Original section

    private var originalSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("原文", systemImage: "text.alignleft")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(originalText)
                .font(.system(size: 13))
                .foregroundStyle(.primary.opacity(0.75))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: Result section

    @ViewBuilder
    private var resultSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(isDone ? "AI \(action.rawValue)版" : "生成中…", systemImage: "sparkles")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.purple)
            Text(result.isEmpty ? " " : result)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.purple.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.purple.opacity(0.2), lineWidth: 1)
                        )
                )
        }
    }

    // MARK: Error section

    private func errorSection(_ msg: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(msg)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Spacer()
            Button("放弃") { dismiss() }
                .keyboardShortcut(.escape, modifiers: [])
            if isDone && !result.isEmpty {
                Button("接受并替换") { acceptAndReplace() }
                    .keyboardShortcut(.return, modifiers: [.command])
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: Actions

    private func startProcessing() {
        guard !isRunning else { return }
        isRunning = true
        isDone    = false
        result    = ""
        errorMsg  = nil

        streamTask = agent.process(
            text: originalText,
            action: action,
            settings: settings,
            pluginManager: state.pluginManager,
            onChunk: { [self] chunk in
                result += chunk
            },
            onComplete: { [self] _, error in
                isRunning = false
                isDone    = true
                if let error {
                    errorMsg = (error as? AIError)?.errorDescription ?? error.localizedDescription
                }
            }
        )
    }

    private func acceptAndReplace() {
        state.replaceInEditor(result)
        state.pendingReplaceRange = nil
        dismiss()
    }
}
