import Foundation

// MARK: - 定时任务配置（schedules.json，纯逻辑可单测）
//
// 配置来源两处，工作区级覆盖全局同名条目（与 mcp.json / skills 同一惯例）：
//   全局：    ~/.meditor/schedules.json
//   工作区：  <工作区>/.meditor/schedules.json
//
// 格式：
//   {"schedules": [{"name": "...", "cron": "0 9 * * 1-5", "prompt": "...", "enabled": true}]}
//
// 容错原则：单个坏条目（缺字段 / 非法 cron / 空 prompt）跳过并记录到 issues，
// 不拖垮整个加载。issues 文案仅供诊断展示，不做本地化（同 mcp.json 惯例）。

/// 一条定时任务配置。
struct ScheduledTaskConfig: Sendable, Equatable, Identifiable {
    /// 配置来源（设置页展示来源徽标；启用开关写回对应来源的文件）
    enum Source: String, Sendable, Equatable {
        case global
        case workspace
    }

    var id: String { name }
    var name: String
    /// cron 表达式原文（展示用）
    var cron: String
    var prompt: String
    var enabled: Bool
    /// 解析后的调度（加载时已校验，非法 cron 的条目不会出现在结果里）
    var schedule: CronSchedule
    var source: Source
}

/// schedules.json 加载结果：合法条目 + 跳过的坏条目说明（供设置页/日志展示）。
struct ScheduledTaskConfigLoadResult: Sendable {
    var entries: [ScheduledTaskConfig]
    var issues: [String]
}

enum ScheduledTaskConfigLoader {

    /// 全局配置文件路径（~/.meditor/schedules.json）。
    static var defaultGlobalConfigURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".meditor/schedules.json")
    }

    /// 工作区级配置文件路径（<root>/.meditor/schedules.json）。
    static func workspaceConfigURL(root: URL) -> URL {
        root.appendingPathComponent(".meditor/schedules.json")
    }

    /// 加载并合并全局 + 工作区配置（工作区同名条目覆盖全局，位置保持全局处）。
    /// 文件不存在视为空配置。
    static func load(globalConfigURL: URL = defaultGlobalConfigURL,
                     workspaceRoot: URL? = nil) -> ScheduledTaskConfigLoadResult {
        var merged: [String: ScheduledTaskConfig] = [:]
        var order: [String] = []
        var issues: [String] = []

        var sources: [(source: ScheduledTaskConfig.Source, url: URL)] = [(.global, globalConfigURL)]
        if let workspaceRoot {
            sources.append((.workspace, workspaceConfigURL(root: workspaceRoot)))
        }

        for source in sources {
            guard let data = FileManager.default.contents(atPath: source.url.path) else { continue }
            let parsed = parse(data: data, source: source.source)
            issues.append(contentsOf: parsed.issues)
            for entry in parsed.entries {
                if merged[entry.name] == nil { order.append(entry.name) }
                merged[entry.name] = entry   // 后加载的（工作区）覆盖同名
            }
        }

        return ScheduledTaskConfigLoadResult(entries: order.compactMap { merged[$0] }, issues: issues)
    }

    /// 解析单个 schedules.json 文件内容。坏条目跳过并记录，不抛错。
    static func parse(data: Data, source: ScheduledTaskConfig.Source) -> ScheduledTaskConfigLoadResult {
        var issues: [String] = []
        let label = source.rawValue

        let obj: Any
        do {
            obj = try JSONSerialization.jsonObject(with: data)
        } catch {
            return ScheduledTaskConfigLoadResult(
                entries: [], issues: ["\(label): invalid JSON (\(error.localizedDescription))"])
        }
        guard let root = obj as? [String: Any] else {
            return ScheduledTaskConfigLoadResult(entries: [], issues: ["\(label): root is not a JSON object"])
        }
        guard let list = root["schedules"] as? [Any] else {
            if root["schedules"] != nil {
                issues.append("\(label): 'schedules' is not an array")
            }
            return ScheduledTaskConfigLoadResult(entries: [], issues: issues)
        }

        var entries: [ScheduledTaskConfig] = []
        for (index, item) in list.enumerated() {
            guard let entry = item as? [String: Any] else {
                issues.append("\(label): entry #\(index + 1) is not an object — skipped")
                continue
            }
            let parsed = parseEntry(entry)
            if let config = parsed.config {
                entries.append(ScheduledTaskConfig(name: config.name, cron: config.cron,
                                                   prompt: config.prompt, enabled: config.enabled,
                                                   schedule: config.schedule, source: source))
            } else if let reason = parsed.issue {
                issues.append("\(label): entry #\(index + 1) \(reason) — skipped")
            }
        }
        return ScheduledTaskConfigLoadResult(entries: entries, issues: issues)
    }

    /// 解析单个条目；失败原因用于 issues 记录（模式同 MCPClientConfigLoader.parseEntry）。
    private static func parseEntry(_ entry: [String: Any])
        -> (config: (name: String, cron: String, prompt: String, enabled: Bool,
                     schedule: CronSchedule)?, issue: String?) {
        guard let rawName = entry["name"] as? String else {
            return (nil, "has a missing or non-string 'name'")
        }
        let name = rawName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return (nil, "has an empty 'name'") }

        guard let rawCron = entry["cron"] as? String,
              let schedule = CronSchedule.parse(rawCron) else {
            return (nil, "has an invalid 'cron'")
        }

        guard let rawPrompt = entry["prompt"] as? String else {
            return (nil, "has a missing or non-string 'prompt'")
        }
        let prompt = rawPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return (nil, "has an empty 'prompt'") }

        // enabled 缺省视为 true（手写配置的最少字段就是 name/cron/prompt）
        let enabled = (entry["enabled"] as? Bool) ?? true
        return ((name, rawCron, prompt, enabled, schedule), nil)
    }
}

// MARK: - 配置写回（设置页启用开关）

enum ScheduledTaskConfigWriter {

    /// 无配置文件时写入的示例模板（JSON 不支持注释，用 _comment 字段 + 停用的示例条目说明格式）。
    static let template = """
    {
      "_comment": "cron = 分 时 日 月 周（本地时区），支持 * , - */n；enabled=false 的条目不触发",
      "schedules": [
        {
          "name": "example-weekly-digest",
          "cron": "0 9 * * 1-5",
          "prompt": "把昨天的日记汇总成周报草稿，写入 weekly/ 目录",
          "enabled": false
        }
      ]
    }
    """

    /// 切换某条目的启用状态：读文件 → 改该条目的 enabled → 整体重写。
    /// 其余字段经 JSONSerialization round-trip 原样保留（JSON 无注释可言，重写即可）。
    /// 找不到同名条目或文件不存在时抛错（调用方 toast）。
    static func setEnabled(_ enabled: Bool, forName name: String, configURL: URL) throws {
        let data = try Data(contentsOf: configURL)
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var list = root["schedules"] as? [[String: Any]] else {
            throw NSError(domain: "MEditor.Schedules", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "not a valid schedules.json"])
        }
        guard let index = list.firstIndex(where: { ($0["name"] as? String) == name }) else {
            throw NSError(domain: "MEditor.Schedules", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "entry '\(name)' not found"])
        }
        list[index]["enabled"] = enabled
        root["schedules"] = list
        let out = try JSONSerialization.data(withJSONObject: root,
                                             options: [.prettyPrinted, .sortedKeys])
        try out.write(to: configURL, options: .atomic)
    }
}
