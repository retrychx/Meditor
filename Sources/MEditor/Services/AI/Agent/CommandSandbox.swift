import Foundation

// MARK: - CommandRisk

/// 命令风险等级。
/// - `.safe`    — 可直接执行（或走普通确认流程）
/// - `.warn`    — 高风险，每次都必须弹确认，不复用缓存
/// - `.blocked` — 直接拒绝，不弹确认框
public enum CommandRisk: Equatable, Sendable {
    case safe
    case warn(reason: String)
    case blocked(reason: String)

    public var isBlocked: Bool {
        if case .blocked = self { return true }
        return false
    }

    /// 供 UI 显示的风险说明文字；.safe 返回 nil。
    public var message: String? {
        switch self {
        case .safe:              return nil
        case .warn(let r):       return r
        case .blocked(let r):    return r
        }
    }
}

// MARK: - CwdValidation

/// 工作目录合规性校验结果。
public enum CwdValidation: Equatable, Sendable {
    case allowed(resolved: String)
    case outsideWorkspace(path: String, workspaceRoot: String)
    case traversalDetected(path: String)

    public var isAllowed: Bool {
        if case .allowed = self { return true }
        return false
    }

    /// 失败时给用户/工具层的错误描述。
    public var errorMessage: String? {
        switch self {
        case .allowed:
            return nil
        case .outsideWorkspace(let path, let root):
            return "安全限制：工作目录 \(path) 不在工作区内（\(root)），已拒绝。"
        case .traversalDetected(let path):
            return "安全限制：检测到路径穿越（\(path)），已拒绝。"
        }
    }
}

// MARK: - CommandSandbox

/// 纯静态的命令安全分析器，无副作用，完全可单测。
///
/// 职责：
///   1. 风险等级评估（blocked → warn → safe）
///   2. 工作目录合规性校验（必须在 workspace root 内）
///   3. 审批 key 生成（用于去重确认，避免相同命令反复弹窗）
///
/// 所有方法都是 `static`，不持有任何状态。
public enum CommandSandbox {

    // MARK: - Risk Rules

    /// 一条风险匹配规则（子串匹配，不区分大小写）。
    public struct RiskRule: Sendable {
        /// 被检测的命令字符串（小写）中需包含的子串。
        public let pattern: String
        /// 风险类型（blocked / warn），risk.message 由 assess 生成，rule 只提供 label。
        public let label: String
        /// 规则描述（用于生成 message）。
        public let description: String
    }

    /// 直接拒绝，不弹确认框。匹配第一条即止。
    public static let blockedRules: [RiskRule] = [
        .init(pattern: "rm -rf /",           label: "blocked", description: "删除根目录"),
        .init(pattern: "rm -rf ~",            label: "blocked", description: "删除 home 目录"),
        .init(pattern: "rm -rf $home",        label: "blocked", description: "删除 home 目录"),
        .init(pattern: ":(){ :|:& };",        label: "blocked", description: "Fork 炸弹"),
        .init(pattern: "mkfs",                label: "blocked", description: "磁盘格式化"),
        .init(pattern: "dd if=",              label: "blocked", description: "磁盘低级写入"),
        .init(pattern: "> /dev/",             label: "blocked", description: "写入设备文件"),
        .init(pattern: "sudo ",               label: "blocked", description: "sudo 提权"),
        .init(pattern: "sudo\t",              label: "blocked", description: "sudo 提权（tab）"),
        .init(pattern: "su -",                label: "blocked", description: "切换 root"),
        .init(pattern: "chmod 777 /",         label: "blocked", description: "系统目录权限篡改"),
        .init(pattern: "chown -r /",          label: "blocked", description: "系统目录 owner 篡改"),
        .init(pattern: "defaults delete com.apple", label: "blocked", description: "删除系统级 defaults"),
        .init(pattern: "curl ",               label: "blocked", description: "外部网络请求（含 pipe shell 风险）"),
        .init(pattern: "wget ",               label: "blocked", description: "外部网络下载"),
        .init(pattern: "killall ",            label: "blocked", description: "批量终止进程"),
        .init(pattern: "launchctl unload",    label: "blocked", description: "卸载系统服务"),
        .init(pattern: "launchctl remove",    label: "blocked", description: "移除系统服务"),
        .init(pattern: "/etc/passwd",         label: "blocked", description: "访问系统账户文件"),
        .init(pattern: "/etc/sudoers",        label: "blocked", description: "访问 sudoers"),
    ]

    /// 高风险：每次都必须弹确认，不复用已缓存的审批 key。
    public static let warnRules: [RiskRule] = [
        .init(pattern: "rm ",               label: "warn", description: "删除文件"),
        .init(pattern: "mv ",               label: "warn", description: "移动 / 重命名（可能覆盖）"),
        .init(pattern: "npm publish",       label: "warn", description: "发布到 npm 公共仓库"),
        .init(pattern: "yarn publish",      label: "warn", description: "发布到 npm 公共仓库"),
        .init(pattern: "pnpm publish",      label: "warn", description: "发布到 npm 公共仓库"),
        .init(pattern: "git push",          label: "warn", description: "推送到远端"),
        .init(pattern: "git reset --hard",  label: "warn", description: "丢弃工作区未提交改动"),
        .init(pattern: "git clean -fd",     label: "warn", description: "清理未跟踪文件"),
        .init(pattern: "git force-push",    label: "warn", description: "强制推送"),
        .init(pattern: "drop table",        label: "warn", description: "SQL 删表"),
        .init(pattern: "drop database",     label: "warn", description: "SQL 删库"),
        .init(pattern: "truncate table",    label: "warn", description: "SQL 清空表"),
    ]

    // MARK: - Assess

    /// 评估命令风险等级。纯函数，无副作用。
    ///
    /// 匹配优先级：blocked > warn > safe。
    /// 返回的 `.warn`/`.blocked` 中已包含用户可读的 reason 文字。
    public static func assess(_ command: String) -> CommandRisk {
        let lower = command.lowercased().trimmingCharacters(in: .whitespaces)
        guard !lower.isEmpty else { return .safe }

        for rule in blockedRules where lower.contains(rule.pattern) {
            return .blocked(reason: "🚫 安全限制：\(rule.description)，该命令已被自动拒绝。\n命令：\(truncated(command))")
        }

        for rule in warnRules where lower.contains(rule.pattern) {
            return .warn(reason: "⚠️ 高风险操作：\(rule.description)，请确认后继续。")
        }

        return .safe
    }

    // MARK: - Cwd Validation

    /// 校验 cwd 是否在 workspaceRoot 内。
    ///
    /// - Parameters:
    ///   - cwd: 工具层传入的工作目录（绝对路径或相对路径）。
    ///   - workspaceRoot: 当前 workspace 根目录。nil 表示未打开 workspace，此时不限制。
    public static func validateCwd(_ cwd: String, workspaceRoot: String?) -> CwdValidation {
        let trimmed = cwd.trimmingCharacters(in: .whitespaces)

        // 未打开 workspace → 不作限制
        guard let root = workspaceRoot, !root.isEmpty else {
            return .allowed(resolved: trimmed.isEmpty ? "" : trimmed)
        }

        let canonical     = URL(fileURLWithPath: trimmed).standardizedFileURL.path
        let rootCanonical = URL(fileURLWithPath: root).standardizedFileURL.path

        // 路径穿越检测（规范化后仍在 root 内则允许）
        if trimmed.contains("../") || trimmed.hasSuffix("/..") || trimmed == ".." {
            if !canonical.hasPrefix(rootCanonical) {
                return .traversalDetected(path: cwd)
            }
        }

        if canonical == rootCanonical || canonical.hasPrefix(rootCanonical + "/") {
            return .allowed(resolved: canonical)
        }

        return .outsideWorkspace(path: canonical, workspaceRoot: rootCanonical)
    }

    // MARK: - Approval Key

    /// 生成命令审批 key，用于 per-command 去重确认缓存。
    ///
    /// 设计原则：相同 command + cwd 组合复用已有的确认；
    /// 不同命令或不同目录视为独立操作，各自需要用户确认。
    ///
    /// 注意：warn 级别命令不应被缓存——调用方负责在检测到 warn 时
    /// 跳过 key 检查，直接弹确认框。
    public static func approvalKey(command: String, cwd: String?) -> String {
        let cmd = command.trimmingCharacters(in: .whitespaces)
        let dir = cwd?.trimmingCharacters(in: .whitespaces) ?? ""
        // 用竖线分隔，两部分均可能含空格，不影响唯一性
        return "\(cmd)|\(dir)"
    }

    // MARK: - Allowed Commands Check

    /// 检查命令是否符合 allowedCommandPatterns（skill SKILL.md 中声明的白名单）。
    ///
    /// - Parameters:
    ///   - command:  要执行的命令字符串。
    ///   - patterns: 允许的命令前缀列表。nil 表示不限制（允许所有）。
    /// - Returns: `true` 表示命令在白名单内或白名单为空；`false` 表示被白名单拒绝。
    public static func matchesAllowedPatterns(_ command: String, patterns: [String]?) -> Bool {
        guard let patterns, !patterns.isEmpty else { return true }
        let cmd = command.trimmingCharacters(in: .whitespaces)
        return patterns.contains { cmd.hasPrefix($0) }
    }

    // MARK: - Private Helpers

    private static func truncated(_ s: String, maxLength: Int = 80) -> String {
        s.count <= maxLength ? s : String(s.prefix(maxLength)) + "…"
    }
}
