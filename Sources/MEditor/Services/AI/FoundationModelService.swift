import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - 端侧模型可用性抽象

/// 端侧模型（Apple Foundation Models）可用性的自有抽象。
/// 业务代码只依赖本枚举与下方 `OnDeviceModelProviding` 协议，不直接
/// import FoundationModels——这样单元测试可以用 mock 覆盖所有状态，
/// 不需要真机模型。
enum OnDeviceModelAvailability: Equatable, Sendable {
    /// 可以直接发起端侧推理。
    case available
    /// 不可用；原因见 `UnavailabilityReason`。
    case unavailable(UnavailabilityReason)

    enum UnavailabilityReason: Equatable, Sendable {
        /// 系统版本/编译环境没有 FoundationModels 框架（如 macOS 26 以下）。
        case unsupportedOS
        /// 硬件/机型不支持 Apple 智能。
        case deviceNotEligible
        /// 系统设置里没开启 Apple 智能。
        case appleIntelligenceNotEnabled
        /// 模型资源还在下载/准备中。
        case modelNotReady
        /// 其他未识别原因。
        case unknown
    }

    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    /// 设置页状态展示的本地化 key（见 Localization.swift 端侧智能小节）。
    var statusLabelKey: String {
        switch self {
        case .available:
            return "ai.onDevice.available"
        case .unavailable(let reason):
            switch reason {
            case .unsupportedOS:                return "ai.onDevice.unsupportedOS"
            case .deviceNotEligible:            return "ai.onDevice.deviceNotEligible"
            case .appleIntelligenceNotEnabled:  return "ai.onDevice.notEnabled"
            case .modelNotReady:                return "ai.onDevice.modelNotReady"
            case .unknown:                      return "ai.onDevice.unknown"
            }
        }
    }
}

// MARK: - 端侧模型协议

/// 端侧模型提供方协议。正式实现走 FoundationModels（macOS 26+），
/// 测试用 mock 注入，业务层永远面向协议。
protocol OnDeviceModelProviding: Sendable {
    /// 当前可用性（同步、廉价；FoundationModels 的探测本身是本地状态读取）。
    var availability: OnDeviceModelAvailability { get }
    /// 通用指令跟随生成：instructions 是会话级指令，prompt 是本次输入。
    func generate(instructions: String, prompt: String) async throws -> String
}

// MARK: - FoundationModels 正式实现

#if canImport(FoundationModels)
/// 走系统端侧模型的真实实现。仅 macOS 26+ 可实例化。
@available(macOS 26, *)
struct SystemOnDeviceModelProvider: OnDeviceModelProviding {

    var availability: OnDeviceModelAvailability {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return .unavailable(.deviceNotEligible)
            case .appleIntelligenceNotEnabled:
                return .unavailable(.appleIntelligenceNotEnabled)
            case .modelNotReady:
                return .unavailable(.modelNotReady)
            @unknown default:
                return .unavailable(.unknown)
            }
        @unknown default:
            return .unavailable(.unknown)
        }
    }

    func generate(instructions: String, prompt: String) async throws -> String {
        // 每次调用新建会话：任务彼此独立（如粘贴清理），不需要跨调用上下文
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: prompt)
        return response.content
    }
}
#endif

// MARK: - FoundationModelService

/// 端侧可选能力门面。@MainActor：可用性探测与调用入口都在主线程完成，
/// 实际的模型推理由 FoundationModels 内部调度，不阻塞主线程。
/// 所有失败路径（不支持 / 未开启 / 生成异常 / 超时 / 空输出）都由调用方
/// 静默回退到原有处理，本服务自身不弹任何错误。
@MainActor
final class FoundationModelService {

    static let shared = FoundationModelService()

    /// 单次端侧生成的超时（秒）。超时按失败处理（调用方回退原始结果）。
    let generateTimeout: TimeInterval

    /// 底层提供方；nil = 当前系统/编译环境没有端侧模型能力。
    let provider: OnDeviceModelProviding?

    private init() {
        self.provider = Self.makeSystemProvider()
        self.generateTimeout = 3
    }

    /// 测试注入入口：mock provider + 自定义超时。
    init(provider: OnDeviceModelProviding?, generateTimeout: TimeInterval = 3) {
        self.provider = provider
        self.generateTimeout = generateTimeout
    }

    /// 构造系统端侧模型提供方；框架缺失或系统版本不足时返回 nil。
    private static func makeSystemProvider() -> OnDeviceModelProviding? {
#if canImport(FoundationModels)
        if #available(macOS 26, *) {
            return SystemOnDeviceModelProvider()
        }
        return nil
#else
        return nil
#endif
    }

    /// 当前端侧可用性。无 provider 时归为「系统不支持」。
    var availability: OnDeviceModelAvailability {
        provider?.availability ?? .unavailable(.unsupportedOS)
    }

    // MARK: 通用生成

    /// 通用指令跟随生成。模型不可用时抛错（调用方自行决定回退策略）。
    /// 带超时护栏：超时抛错，底层任务协作取消。
    func generate(instructions: String, prompt: String) async throws -> String {
        guard let provider, availability.isAvailable else {
            throw OnDeviceModelError.unavailable
        }
        let timeout = generateTimeout
        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await provider.generate(instructions: instructions, prompt: prompt)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw OnDeviceModelError.timedOut
            }
            // 取先完成的那个；另一个协作取消（模型任务收到 cancel 后应尽快退出）
            defer { group.cancelAll() }
            guard let first = try await group.next() else {
                throw OnDeviceModelError.unavailable
            }
            return first
        }
    }

    // MARK: 粘贴内容清理

    /// 粘贴 HTML→Markdown 结果的端侧清理：去除广告/推广/追踪参数/页脚导航，
    /// 保持正文与 Markdown 结构原样。
    ///
    /// 静默回退语义（不抛错）：设置关闭 / 模型不可用 / 生成失败 / 超时 /
    /// 输出为空，一律返回原始 `markdown`——粘贴行为与功能不存在时完全一致。
    func cleanPastedMarkdown(_ markdown: String, enabled: Bool) async -> String {
        guard enabled, !markdown.isEmpty, availability.isAvailable else { return markdown }
        do {
            let cleaned = try await generate(
                instructions: Self.cleanupInstructions,
                prompt: Self.cleanupPrompt(for: markdown)
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? markdown : cleaned
        } catch {
            // 静默回退：清理是尽力而为的增强，绝不影响粘贴主流程
            return markdown
        }
    }

    /// 清理任务的会话级指令（英文写死，模型行为更稳；约束包含「不总结不改写」）。
    static let cleanupInstructions = """
    You are a Markdown cleanup assistant. The user pastes content copied from \
    web pages (blogs, WeChat articles, news sites). Remove ONLY junk: \
    advertisements, promotional blocks, "follow us / click to subscribe" calls to \
    action, footer navigation, related-links sections, and tracking query \
    parameters in URLs (e.g. utm_*,spm,from=). Keep the article body and its \
    Markdown structure (headings, lists, links, images, code blocks) exactly as \
    they are. Do not summarize. Do not rewrite, translate, or paraphrase any \
    sentence. Do not add commentary or explanations. Output only the cleaned \
    Markdown, nothing else.
    """

    /// 清理任务的单次输入：正文包在分隔符内，避免与指令混淆。
    static func cleanupPrompt(for markdown: String) -> String {
        "Clean the following pasted Markdown content:\n\n<content>\n\(markdown)\n</content>"
    }
}

// MARK: - 错误

enum OnDeviceModelError: Error {
    /// 模型不可用（未开启/不支持/无 provider）。
    case unavailable
    /// 生成超时。
    case timedOut
}
