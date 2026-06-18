import SwiftUI

/// Drives thumbnail layout and accent color for each template type.
enum TemplateKind {
    case blank, meeting, tech, weekly, journal, htmlTheme, generic

    init(_ t: DocumentTemplate) {
        switch t.category {
        case .htmlTheme:
            self = .htmlTheme
        case .user, .markdown:
            let n = t.name.lowercased(), id = t.id.lowercased()
            if id == "blank" || n.contains("空白") || n.contains("blank")         { self = .blank }
            else if id.contains("meeting") || n.contains("会议")                   { self = .meeting }
            else if id.contains("tech") || n.contains("技术")                      { self = .tech }
            else if id.contains("weekly") || n.contains("周报")                    { self = .weekly }
            else if id.contains("journal") || n.contains("日记") || n.contains("日报") { self = .journal }
            else                                                                    { self = .generic }
        }
    }

    var accent: Color {
        switch self {
        case .blank:     return .gray
        case .meeting:   return .blue
        case .tech:      return .purple
        case .weekly:    return .green
        case .journal:   return .orange
        case .htmlTheme: return .teal
        case .generic:   return .accentColor
        }
    }
}
