import Foundation

// MARK: - 共享错误类型替身
//
// PatchNotFoundError / AgentContextError 在 macOS 端定义于
// Services/AI/Agent/AgentContext.swift；该文件同时含有依赖 AppState 的
// AgentContext 协调层，无法编进 iOS target。这里把两个纯错误类型按
// macOS 定义原样复制给移动端 target 使用（仅 iOS target 编译本文件，无冲突）。

struct PatchNotFoundError: LocalizedError {
    let find: String
    let nearbyContext: String
    var errorDescription: String? {
        "[!] 未找到匹配文本：「\(find.prefix(60))」\n\n\(nearbyContext)\n\n建议：请用 read_document 重新读取文件内容，确认目标文本后再 patch。"
    }
}

enum AgentContextError: LocalizedError {
    case noWorkspace
    case noActiveDocument
    case fileAlreadyExists(String)
    case fileNotReadable(String)
    case fileNotFound(String)
    case fileTooLarge(String, Int)
    case pathOutsideWorkspace(String)

    var errorDescription: String? {
        switch self {
        case .noWorkspace:                return "未打开工作区"
        case .noActiveDocument:           return "没有激活的文档"
        case .fileAlreadyExists(let n):   return "文件已存在：\(n)"
        case .fileNotReadable(let n):     return "文件无法读取（编码不支持）：\(n)"
        case .fileNotFound(let n):        return "未找到文件：\(n)"
        case .fileTooLarge(let n, let s): return "文件过大（\(s / 1000)KB），超出上限 \(DefaultAgentFileRepository.maxFullReadBytes / 1_000_000)MB：\(n)"
        case .pathOutsideWorkspace(let p): return "安全限制：目标路径不在工作区内（\(p)），已拒绝写入。"
        }
    }
}
