import SwiftUI

// MARK: - 首启引导决策（纯逻辑，便于单测）

enum AIOnboardingLogic {
    /// 是否展示引导：从未配置任何 AI provider 且用户未跳过。
    /// 配置完成后 isConfigured 变 true，引导自动消失（无需额外标记）。
    static func shouldShow(isConfigured: Bool, dismissed: Bool) -> Bool {
        !isConfigured && !dismissed
    }
}

// MARK: - AIOnboardingView

/// 无 AI 配置时的首启引导（嵌入 AI 助手面板空态，不新造窗口）。
/// 路径优先级：检测到 Claude Code → 一键零配置；否则跳设置页填 key；或暂时跳过。
/// 在引导内完成配置后切到「就绪」阶段，给出 30 秒演示入口。
@MainActor
struct AIOnboardingView: View {
    let theme: PreviewTheme
    /// 当前是否已有可用 AI 配置（外部计算传入，驱动 setup → ready 切换）
    let isConfigured: Bool
    /// 当前 provider 是否为 ClaudeCLI（决定就绪阶段跑不跑 CLI 自检）
    let isCLIProvider: Bool
    /// CLI 连接自检（外部注入，复用 AIClient.testClaudeCLI）；返回 nil = 成功
    let cliTest: () async -> String?
    let onUseClaudeCLI: (String) -> Void
    let onOpenSettings: () -> Void
    let onRunDemo: () -> Void
    /// 关闭引导（跳过 / 就绪后「开始对话」）
    let onDismiss: () -> Void

    /// CLI 探测三态：probing 期间不闪烁「未检测到」
    enum CLIDetection: Equatable {
        case probing
        case found(String)
        case notFound
    }
    @State private var detection: CLIDetection = .probing
    /// 本次引导会话内完成了配置 → 停在 ready 阶段（否则 isConfigured 后引导直接消失，
    /// 演示入口来不及展示）
    @State private var configuredInSession = false
    @State private var cliTesting = false
    @State private var cliTestError: String?? = nil   // 外层 nil = 未测；内层 nil = 成功

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.lg) {
                header
                if isConfigured && configuredInSession {
                    readySection
                } else {
                    setupSection
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            DotGridBackground(opacity: theme.isDark ? 0.10 : 0.18)
                .allowsHitTesting(false)
        )
        .task {
            // 登录 shell 探测 + 常见路径扫描，可能耗时几百毫秒，异步进行
            if let path = await AIClient.detectClaudeCLI() {
                detection = .found(path)
            } else {
                detection = .notFound
            }
        }
        .onChange(of: isConfigured) { _, configured in
            if configured && !configuredInSession {
                configuredInSession = true
                runCLITestIfNeeded()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                AIAssistantOrb(size: 36, glow: true)
                Text(isConfigured && configuredInSession ? "AI 已就绪" : "先配置 AI，30 秒搞定")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.craftPrimary)
            }
            if !(isConfigured && configuredInSession) {
                Text("MEditor 的 AI 助手可以帮你整理、改写、生成文档。选择一种方式开始：")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.craftSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 配置阶段

    private var setupSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            // 首选：Claude Code 零配置
            claudeCLICard

            // 次选：预设 provider 填 key（跳设置页 AI tab）
            Button(action: onOpenSettings) {
                HStack(spacing: 10) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 26, height: 26)
                        .foregroundStyle(AIBrand.orange)
                        .background(AIBrand.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("配置其他 AI 服务")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(theme.craftPrimary)
                        Text("OpenAI / DeepSeek / Kimi / GLM… 填 API Key")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.craftSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(theme.craftSecondary)
                }
                .padding(10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .fill(theme.craftHover.opacity(0.5))
            )

            Button("暂时跳过", action: onDismiss)
                .buttonStyle(.plain)
                .font(.system(size: 11.5))
                .foregroundStyle(theme.craftSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 2)
        }
    }

    private var claudeCLICard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 26, height: 26)
                    .foregroundStyle(AIBrand.blue)
                    .background(AIBrand.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text("使用 Claude Code")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(theme.craftPrimary)
                        Text("推荐")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(AIBrand.blue, in: Capsule())
                    }
                    switch detection {
                    case .probing:
                        Text("正在检测本机 Claude Code…")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.craftSecondary)
                    case .found(let path):
                        Text("已检测到：\(path)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(theme.craftSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    case .notFound:
                        Text("未检测到。已安装 Claude Code 可免 Key 零配置使用")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.craftSecondary)
                    }
                }
                Spacer()
            }

            if case .found(let path) = detection {
                Button {
                    onUseClaudeCLI(path)
                } label: {
                    Text("直接使用（免 API Key）")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(AIBrand.blue, in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .fill(AIBrand.blue.opacity(theme.isDark ? 0.10 : 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .strokeBorder(AIBrand.blue.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - 就绪阶段（引导内完成配置后）

    private var readySection: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            // CLI 自检结果（仅 ClaudeCLI provider）
            if isCLIProvider {
                HStack(spacing: 6) {
                    if cliTesting {
                        ProgressView().controlSize(.small)
                        Text("正在验证连接…")
                    } else if let result = cliTestError {
                        if let error = result {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                            Text("连接失败：\(error)")
                        } else {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            Text("连接正常，可以开始对话")
                        }
                    }
                }
                .font(.system(size: 11.5))
                .foregroundStyle(theme.craftSecondary)
                .lineLimit(2)
            }

            Button(action: onRunDemo) {
                HStack(spacing: 10) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 26, height: 26)
                        .foregroundStyle(.white)
                        .background(AIBrand.violet, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("看一个 30 秒演示")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(theme.craftPrimary)
                        Text("Agent 自动整理一篇示例会议记录（写在临时目录，不动你的文件）")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.craftSecondary)
                    }
                    Spacer()
                }
                .padding(10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .fill(AIBrand.violet.opacity(theme.isDark ? 0.12 : 0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .strokeBorder(AIBrand.violet.opacity(0.25), lineWidth: 1)
            )

            Button("直接开始对话", action: onDismiss)
                .buttonStyle(.plain)
                .font(.system(size: 11.5))
                .foregroundStyle(theme.craftSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 2)
        }
    }

    // MARK: - Logic

    private func runCLITestIfNeeded() {
        guard isCLIProvider, !cliTesting else { return }
        cliTesting = true
        Task {
            let error = await cliTest()
            cliTestError = error   // 内层 nil = 成功
            cliTesting = false
        }
    }
}
