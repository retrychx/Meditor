import Foundation

// MARK: - Model pricing table

/// 单个模型的价格（每百万 token 的美元价格）。
struct ModelPrice: Sendable, Equatable {
    var input: Double
    var output: Double
    /// 缓存命中读取价（OpenAI cached input / Anthropic cache_read）
    var cacheRead: Double
    /// 缓存写入价（Anthropic cache_write，5min TTL 为 input 的 1.25x；
    /// OpenAI 无缓存写溢价，与 input 同价）
    var cacheWrite: Double
}

/// 内置模型价格表 + 成本估算。
///
/// 来源：各厂商官方定价页（anthropic.com/pricing、openai.com/api/pricing、
/// platform.deepseek.com、platform.moonshot.cn、bigmodel.cn、
/// help.aliyun.com、ai.google.dev/pricing、console.groq.com），整理于 2026 年初。
/// ⚠️ 价格随厂商调整会过时——本表只用于「数量级」成本提示，不作为对账依据；
/// 查不到的模型降级为只显示 token 数（estimateCost 返回 nil）。
enum ModelPricing {

    /// 匹配规则：模型名先去掉 OpenRouter 风格前缀（"anthropic/…"），小写后做
    /// 最长前缀匹配（如 "claude-sonnet-4-5-20250929" 命中 "claude-sonnet-4-5"）。
    private static let table: [(prefix: String, price: ModelPrice)] = [
        // Anthropic（cache_read ≈ input×0.1，cache_write ≈ input×1.25）
        ("claude-opus-4-5",   ModelPrice(input: 5.0,  output: 25.0, cacheRead: 0.5,   cacheWrite: 6.25)),
        ("claude-sonnet-4",   ModelPrice(input: 3.0,  output: 15.0, cacheRead: 0.3,   cacheWrite: 3.75)),
        ("claude-3-7-sonnet", ModelPrice(input: 3.0,  output: 15.0, cacheRead: 0.3,   cacheWrite: 3.75)),
        ("claude-haiku-3-5",  ModelPrice(input: 0.8,  output: 4.0,  cacheRead: 0.08,  cacheWrite: 1.0)),
        // OpenAI（cached input 半价左右，无缓存写溢价）
        ("gpt-4o-mini",       ModelPrice(input: 0.15, output: 0.6,  cacheRead: 0.075, cacheWrite: 0.15)),
        ("gpt-4o",            ModelPrice(input: 2.5,  output: 10.0, cacheRead: 1.25,  cacheWrite: 2.5)),
        ("gpt-4.1-nano",      ModelPrice(input: 0.1,  output: 0.4,  cacheRead: 0.025, cacheWrite: 0.1)),
        ("gpt-4.1-mini",      ModelPrice(input: 0.4,  output: 1.6,  cacheRead: 0.1,   cacheWrite: 0.4)),
        ("gpt-4.1",           ModelPrice(input: 2.0,  output: 8.0,  cacheRead: 0.5,   cacheWrite: 2.0)),
        ("o3-mini",           ModelPrice(input: 1.1,  output: 4.4,  cacheRead: 0.55,  cacheWrite: 1.1)),
        ("o3",                ModelPrice(input: 2.0,  output: 8.0,  cacheRead: 0.5,   cacheWrite: 2.0)),
        ("o1-pro",            ModelPrice(input: 150.0, output: 600.0, cacheRead: 150.0, cacheWrite: 150.0)),
        ("o1",                ModelPrice(input: 15.0, output: 60.0, cacheRead: 7.5,   cacheWrite: 15.0)),
        // DeepSeek（V3 系列挂牌价，命中缓存 0.07；v4 价格未公布，暂按同档近似）
        ("deepseek",          ModelPrice(input: 0.27, output: 1.1,  cacheRead: 0.07,  cacheWrite: 0.27)),
        // Moonshot Kimi（k2 命中缓存 0.15）
        ("kimi-k2",           ModelPrice(input: 0.6,  output: 2.5,  cacheRead: 0.15,  cacheWrite: 0.6)),
        // 智谱 GLM（国际站美元价近似；glm-4-flash 免费档不收录，降级为只显示 token）
        ("glm-4.6",           ModelPrice(input: 0.6,  output: 2.2,  cacheRead: 0.11,  cacheWrite: 0.6)),
        ("glm-4-plus",        ModelPrice(input: 7.0,  output: 7.0,  cacheRead: 1.4,   cacheWrite: 7.0)),
        // 通义千问（国际站美元价）
        ("qwen-max",          ModelPrice(input: 1.6,  output: 6.4,  cacheRead: 0.32,  cacheWrite: 1.6)),
        ("qwen-plus",         ModelPrice(input: 0.4,  output: 1.2,  cacheRead: 0.08,  cacheWrite: 0.4)),
        ("qwen-turbo",        ModelPrice(input: 0.05, output: 0.2,  cacheRead: 0.01,  cacheWrite: 0.05)),
        // Google Gemini
        ("gemini-2.0-flash",  ModelPrice(input: 0.1,  output: 0.4,  cacheRead: 0.025, cacheWrite: 0.1)),
        // Groq 托管开源模型
        ("llama-3.3-70b",     ModelPrice(input: 0.59, output: 0.79, cacheRead: 0.59,  cacheWrite: 0.59)),
        ("llama-3.1-8b",      ModelPrice(input: 0.05, output: 0.08, cacheRead: 0.05,  cacheWrite: 0.05)),
        ("mixtral-8x7b",      ModelPrice(input: 0.24, output: 0.24, cacheRead: 0.24,  cacheWrite: 0.24)),
    ]

    /// 查模型价格；查不到返回 nil（UI 降级为只显示 token 数）。
    static func price(for model: String) -> ModelPrice? {
        var name = model.trimmingCharacters(in: .whitespaces).lowercased()
        guard !name.isEmpty else { return nil }
        // OpenRouter 风格 "vendor/model"：去 vendor 前缀
        if let slash = name.lastIndex(of: "/") {
            name = String(name[name.index(after: slash)...])
        }
        // 版本号写法归一：官方 "claude-3-7-sonnet" 与 OpenRouter "claude-3.7-sonnet"、
        // "gpt-4.1" 等差异通过「小数点 → 连字符」抹平（表内 prefix 同样归一后再比）
        let normalized = name.replacingOccurrences(of: ".", with: "-")
        // 最长前缀匹配：避免 "gpt-4o" 抢在 "gpt-4o-mini" 前面命中
        return table
            .filter { normalized.hasPrefix($0.prefix.replacingOccurrences(of: ".", with: "-")) }
            .max { $0.prefix.count < $1.prefix.count }?
            .price
    }

    /// 估算一次用量（AgentUsage 口径：promptTokens 为全部输入，含缓存部分）的美元成本。
    /// 模型未知或用量为空时返回 nil。
    static func estimateCost(usage: AgentUsage, model: String?) -> Double? {
        guard let model, let price = price(for: model) else { return nil }
        let uncachedInput = max(0, usage.promptTokens - usage.cacheReadTokens - usage.cacheWriteTokens)
        let perMillion = 1_000_000.0
        let cost = Double(uncachedInput) * price.input
            + Double(usage.cacheReadTokens) * price.cacheRead
            + Double(usage.cacheWriteTokens) * price.cacheWrite
            + Double(usage.completionTokens) * price.output
        return cost / perMillion
    }

    /// 紧凑 token 数：999 → "999"，12 345 → "12.3K"，2 345 678 → "2.3M"。
    static func compactTokens(_ n: Int) -> String {
        if n < 1_000 { return "\(n)" }
        if n < 1_000_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return String(format: "%.1fM", Double(n) / 1_000_000)
    }

    /// 美元金额格式化：小额给 4 位小数（单次调用多在 $0.001~$0.01 量级），大额 2 位。
    static func formatUSD(_ cost: Double) -> String {
        cost < 0.1 ? String(format: "$%.4f", cost) : String(format: "$%.2f", cost)
    }
}
