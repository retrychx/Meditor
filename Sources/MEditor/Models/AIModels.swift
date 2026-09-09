import SwiftUI

// MARK: - Conversation models

struct AIChatMessage: Identifiable, Codable, Sendable {
    enum Role: String, Codable, Sendable { case user, assistant }
    var id = UUID()
    let role: Role
    var text: String
    /// 图片附件（仅内存）：base64 体积大，不进会话持久化；编码时只记 imageCount 占位。
    var images: [AIImageAttachment] = []
    /// 持久化的图片数量：重新打开会话后图片数据已丢弃，按此在气泡里渲染占位说明。
    var imageCount: Int = 0

    enum CodingKeys: String, CodingKey {
        case id, role, text, imageCount   // images 故意不编码（见 images 注释）
    }

    init(id: UUID = UUID(), role: Role, text: String, images: [AIImageAttachment] = []) {
        self.id = id
        self.role = role
        self.text = text
        self.images = images
        self.imageCount = images.count
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        role = try c.decode(Role.self, forKey: .role)
        text = try c.decode(String.self, forKey: .text)
        // 旧版 ai-sessions.json 无 imageCount 字段，解码兼容为 0
        imageCount = try c.decodeIfPresent(Int.self, forKey: .imageCount) ?? 0
        images = []
    }
}

struct AISession: Identifiable, Codable, Sendable {
    var id = UUID()
    var title: String = ""
    var messages: [AIChatMessage] = []
    var updatedAt: Date = .now
    /// 保存 AgentRunner 最终消息列表（含工具调用上下文），用于多轮对话时保留 tool context
    var agentHistory: [AgentMessage] = []
    /// 输入框草稿（按会话独立保存，切换/新建会话不再丢失）。
    /// 可选类型保证旧版 ai-sessions.json（无此字段）解码兼容。
    var draft: String? = nil
    /// 会话级累计 token 用量（每次 run 结束时累加；可选类型保证旧数据解码兼容）。
    var cumulativeUsage: AgentUsage? = nil
    /// 最近一次 run 使用的模型名（累计成本估算用；会话可能跨模型，按最近模型近似）
    var lastModel: String? = nil
}

// MARK: - Accent style

/// Selectable accent treatment applied app-wide. `system` uses the app accent
/// (blue); `shadcn` uses a mono near-black / near-white palette
/// (shadcn/ui "primary": light #18181B, dark #FAFAFA).
enum AIAccentStyle: String, CaseIterable, Identifiable {
    case system
    case shadcn

    var id: String { rawValue }

    var labelKey: String {
        switch self {
        case .system: return "ai.accent.system"
        case .shadcn: return "ai.accent.mono"
        }
    }

    /// Button / bubble fill.
    func fill(_ theme: PreviewTheme) -> Color {
        switch self {
        case .system: return .accentColor
        case .shadcn: return theme.isDark ? Color(hex: "FAFAFA") : Color(hex: "18181B")
        }
    }

    /// Foreground (text/icon) drawn on top of `fill`.
    func onFill(_ theme: PreviewTheme) -> Color {
        switch self {
        case .system: return .white
        case .shadcn: return theme.isDark ? Color(hex: "18181B") : Color(hex: "FAFAFA")
        }
    }

    /// Swatch shown in any accent picker.
    func swatch(_ theme: PreviewTheme) -> Color { fill(theme) }

    @MainActor
    static func current(_ settings: AppSettings) -> AIAccentStyle {
        AIAccentStyle(rawValue: settings.aiAccentStyle) ?? .system
    }
}
