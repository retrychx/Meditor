import SwiftUI

// MARK: - Conversation models

struct AIChatMessage: Identifiable, Codable, Sendable {
    enum Role: String, Codable, Sendable { case user, assistant }
    var id = UUID()
    let role: Role
    var text: String
}

struct AISession: Identifiable, Codable, Sendable {
    var id = UUID()
    var title: String = ""
    var messages: [AIChatMessage] = []
    var updatedAt: Date = .now
    /// 保存 AgentRunner 最终消息列表（含工具调用上下文），用于多轮对话时保留 tool context
    var agentHistory: [AgentMessage] = []
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
