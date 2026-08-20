import SwiftUI

/// Sparkle 更新面板（双语 L()、DS 样式）：承载检查/发现/下载/解压/安装/就绪全流程。
/// 状态与按钮回调见 UpdatePanelState / SparkleUserDriver。
struct UpdatePanelView: View {
    let state: UpdatePanelState

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            header
            content
            buttons
        }
        .padding(DS.Space.xl)
        .frame(width: 460)
        .background(DS.Color.editorBg)
    }

    // MARK: - 头部（图标 + 标题）

    @ViewBuilder
    private var header: some View {
        HStack(spacing: DS.Space.md) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(headerTitle)
                    .font(DS.Font.label(15, weight: .semibold))
                if state.phase == .found || state.phase == .downloading
                    || state.phase == .extracting || state.phase == .ready {
                    Text("\(state.currentVersion) → \(state.newVersion)")
                        .font(DS.Font.mono(11))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(DS.Color.pillBg))
                }
            }
            Spacer()
        }
    }

    private var headerTitle: String {
        switch state.phase {
        case .checking: return L("update.title.checking")
        case .permission: return L("update.title.permission")
        case .found: return L("update.title.found")
        case .downloading: return L("update.title.downloading")
        case .extracting: return L("update.title.extracting")
        case .installing: return L("update.title.installing")
        case .ready: return L("update.title.ready")
        case .notFound: return L("update.title.notFound")
        case .failed: return L("update.title.failed")
        }
    }

    // MARK: - 中部内容

    @ViewBuilder
    private var content: some View {
        switch state.phase {
        case .checking:
            HStack(spacing: DS.Space.sm) {
                ProgressView().controlSize(.small)
                Text(L("update.checking"))
                    .font(DS.Font.label())
                    .foregroundStyle(.secondary)
            }

        case .permission:
            Text(L("update.permissionPrompt"))
                .font(DS.Font.label())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

        case .found:
            if let notes = releaseNotes {
                ScrollView {
                    Text(notes)
                        .font(DS.Font.label(12))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(DS.Space.md)
                }
                .frame(maxHeight: 240)
                .background(DS.Color.pillBg)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
            } else {
                Text(L("update.foundNoNotes"))
                    .font(DS.Font.label())
                    .foregroundStyle(.secondary)
            }

        case .downloading:
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                if state.expectedBytes > 0 {
                    ProgressView(value: Double(state.receivedBytes), total: Double(state.expectedBytes))
                    Text("\(formatBytes(state.receivedBytes)) / \(formatBytes(state.expectedBytes))")
                        .font(DS.Font.mono(10.5))
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                    Text(L("update.downloading"))
                        .font(DS.Font.label())
                        .foregroundStyle(.secondary)
                }
            }

        case .extracting:
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                ProgressView(value: state.extractionProgress)
                Text(L("update.extracting"))
                    .font(DS.Font.label())
                    .foregroundStyle(.secondary)
            }

        case .installing:
            HStack(spacing: DS.Space.sm) {
                ProgressView().controlSize(.small)
                Text(L("update.installing"))
                    .font(DS.Font.label())
                    .foregroundStyle(.secondary)
            }

        case .ready:
            Text(L("update.readyMessage"))
                .font(DS.Font.label())
                .foregroundStyle(.secondary)

        case .notFound:
            Text(L("update.notFoundMessage", state.currentVersion))
                .font(DS.Font.label())
                .foregroundStyle(.secondary)

        case .failed:
            Text(state.errorMessage)
                .font(DS.Font.label(12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 底部按钮

    @ViewBuilder
    private var buttons: some View {
        HStack(spacing: DS.Space.sm) {
            Spacer()
            switch state.phase {
            case .checking, .downloading:
                panelButton(L("common.cancel"), role: .secondary) { state.cancelAction?() }
            case .permission:
                panelButton(L("update.disallow"), role: .secondary) { state.secondaryAction?() }
                panelButton(L("update.allowAutoCheck"), role: .primary) { state.primaryAction?() }
            case .found:
                panelButton(L("update.skipVersion"), role: .plain) { state.tertiaryAction?() }
                panelButton(L("update.remindLater"), role: .secondary) { state.secondaryAction?() }
                panelButton(L("update.updateNow"), role: .primary) { state.primaryAction?() }
            case .ready:
                panelButton(L("update.later"), role: .secondary) { state.secondaryAction?() }
                panelButton(L("update.restartNow"), role: .primary) { state.primaryAction?() }
            case .notFound, .failed:
                panelButton(L("common.ok"), role: .primary) { state.primaryAction?() }
            case .extracting, .installing:
                EmptyView()
            }
        }
    }

    private enum ButtonRole { case primary, secondary, plain }

    @ViewBuilder
    private func panelButton(_ title: String, role: ButtonRole, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(DS.Font.label(12.5, weight: role == .primary ? .semibold : .regular))
                .padding(.horizontal, DS.Space.md)
                .padding(.vertical, 5)
                .background(backgroundFor(role))
                .foregroundStyle(foregroundFor(role))
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.sm)
                        .stroke(DS.Color.divider, lineWidth: role == .secondary ? 1 : 0)
                )
        }
        .buttonStyle(.plain)
        .hoverBrightness(0.05)
    }

    private func backgroundFor(_ role: ButtonRole) -> Color {
        switch role {
        case .primary: return .appAccent
        case .secondary: return DS.Color.editorBg
        case .plain: return .clear
        }
    }

    private func foregroundFor(_ role: ButtonRole) -> Color {
        switch role {
        case .primary: return .white
        case .secondary: return .primary
        case .plain: return .secondary
        }
    }

    // MARK: - 更新日志

    /// appcast 的 description 是 HTML 片段；转 AttributedString 用系统字体展示。
    private var releaseNotes: AttributedString? {
        guard let html = state.releaseNotesHTML, !html.isEmpty else { return nil }
        let styled = """
        <style>
        body { font-family: -apple-system; font-size: 12px; }
        ul { padding-left: 18px; margin: 4px 0; }
        li { margin: 2px 0; }
        </style>
        \(html)
        """
        guard let data = styled.data(using: .utf8),
              let ns = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue,
                ],
                documentAttributes: nil
              ) else { return nil }
        return AttributedString(ns)
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
