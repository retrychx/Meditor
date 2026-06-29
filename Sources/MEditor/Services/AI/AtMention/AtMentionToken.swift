import Foundation

// MARK: - AtMention Token (可扩展的 @ 引用类型)

/// 单个 @ 引用的类型。
/// 扩展时只需新增 case——Parser 和 ContextBuilder 通过 switch 匹配，不会遗漏。
enum AtMentionKind: Equatable, Hashable {
    /// 普通文件（读取内容注入上下文）
    case file(url: URL)
    /// 目录（列举子文件名，不展开内容）
    case directory(url: URL)
    /// 当前打开的文档（快捷关键词 @current）
    case currentDocument
    /// 工作区所有文件列表（快捷关键词 @workspace）
    case workspace

    // ── 显示属性 ─────────────────────────────────────────────

    var displayName: String {
        switch self {
        case .file(let url):        return url.lastPathComponent
        case .directory(let url):   return url.lastPathComponent + "/"
        case .currentDocument:      return "current"
        case .workspace:            return "workspace"
        }
    }

    var icon: String {
        switch self {
        case .file:             return "doc.fill"
        case .directory:        return "folder.fill"
        case .currentDocument:  return "doc.text.fill"
        case .workspace:        return "square.grid.2x2.fill"
        }
    }

    var isDirectory: Bool {
        if case .directory = self { return true }
        return false
    }
}

/// 代表输入框里的一个 @ token（已确认引用）。
struct AtMentionToken: Identifiable, Equatable, Hashable {
    let id = UUID()
    let kind: AtMentionKind

    var displayName: String { kind.displayName }
    var icon: String { kind.icon }
}

// MARK: - Candidate（选择器候选项，含搜索匹配分）

/// 选择浮层中的一条候选项。
struct AtMentionCandidate: Identifiable, Equatable {
    let id = UUID()
    let kind: AtMentionKind
    let relPath: String    // 相对工作区根目录的路径，用于显示和排序

    var displayName: String { kind.displayName }
    var icon: String { kind.icon }

    /// 是否为内建快捷关键词（@current / @workspace）
    var isBuiltin: Bool {
        switch kind {
        case .currentDocument, .workspace: return true
        default: return false
        }
    }
}

// MARK: - AtMention 约束

enum AtMentionLimits {
    /// 单条文件内容注入的最大字节数（超过则截断）
    static let maxFileBytesPerToken = 32_000     // ~8K tokens
    /// 单次对话允许 @ 的最大文件数（防止 context 爆炸）
    static let maxTokensPerMessage  = 8
    /// 目录最多展示多少个子文件
    static let maxDirChildren       = 40
}
