import Foundation

// MARK: - CronSchedule（标准 5 字段 cron：分 时 日 月 周，按传入 Calendar 求值）
//
// 支持语法：
//   *              任意值
//   a              具体值
//   a,b,c          列表
//   a-b            范围
//   */n 、a-b/n    步进
// 周字段取值 0-6（0 = 周日；兼容常见写法，7 也按周日处理）。
//
// 日/周并存语义（经典 Vixie cron）：「日」与「周」两字段都不是 * 时，任一命中即触发；
// 否则两者都必须命中。例："0 9 1 * 1" = 每月 1 号或每周一的 09:00。
//
// DST 说明：nextFire 基于 Calendar 的日期组件匹配，不做夏令时特殊处理——
// 春季拨快产生的不存在时刻（如当天 02:30）由 Calendar 解析到相邻有效时间；
// 秋季回拨的重复小时不会重复触发（上层按分钟去重）。这在定时任务场景下可接受。
struct CronSchedule: Equatable, Sendable {

    /// 一个字段的允许值集合。
    struct Field: Equatable, Sendable {
        /// 匹配值集合
        let values: Set<Int>
        /// 升序缓存（nextFire 逐天扫描时按序尝试）
        let sorted: [Int]
        /// 字段原文是否就是 "*"（仅用于日/周并存的 OR 判定）
        let isWildcard: Bool

        func contains(_ v: Int) -> Bool { values.contains(v) }
    }

    let minute: Field       // 0-59
    let hour: Field         // 0-23
    let dayOfMonth: Field   // 1-31
    let month: Field        // 1-12
    let dayOfWeek: Field    // 0-6（0 = 周日）

    // MARK: - 解析

    /// 解析 5 字段 cron 表达式；任何字段非法返回 nil（调用方跳过该条目并记录）。
    static func parse(_ expression: String) -> CronSchedule? {
        let parts = expression.split(separator: " ", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 5 else { return nil }
        guard let minute = parseField(parts[0], range: 0...59),
              let hour = parseField(parts[1], range: 0...23),
              let dayOfMonth = parseField(parts[2], range: 1...31),
              let month = parseField(parts[3], range: 1...12),
              let dayOfWeek = parseField(parts[4], range: 0...7, normalize: { $0 == 7 ? 0 : $0 })
        else { return nil }
        return CronSchedule(minute: minute, hour: hour, dayOfMonth: dayOfMonth,
                            month: month, dayOfWeek: dayOfWeek)
    }

    /// 解析单个字段：逗号分隔的 token 列表，token 为 * / a / a-b / （* 或 a-b）/n。
    /// - Parameter normalize: 值归一化（周字段 7 → 0），nil 表示不变。
    private static func parseField(_ text: String, range: ClosedRange<Int>,
                                   normalize: ((Int) -> Int)? = nil) -> Field? {
        guard !text.isEmpty else { return nil }
        var values = Set<Int>()
        // omittingEmptySubsequences: false —— "1," 这类空 token 要识别为非法
        for rawToken in text.split(separator: ",", omittingEmptySubsequences: false) {
            let token = String(rawToken)
            guard !token.isEmpty else { return nil }

            // 拆出步进（token/n）
            var base = token
            var step = 1
            if let slash = token.firstIndex(of: "/") {
                base = String(token[token.startIndex..<slash])
                let stepText = String(token[token.index(after: slash)...])
                guard let n = Int(stepText), n >= 1 else { return nil }
                step = n
            }

            let lo: Int
            let hi: Int
            if base == "*" {
                lo = range.lowerBound
                hi = range.upperBound
            } else if let dash = base.firstIndex(of: "-") {
                let a = String(base[base.startIndex..<dash])
                let b = String(base[base.index(after: dash)...])
                guard let aV = Int(a), let bV = Int(b),
                      range.contains(aV), range.contains(bV), aV <= bV else { return nil }
                lo = aV
                hi = bV
            } else {
                // 单值不支持 /n 步进（无区间可步进），有步进视为非法
                guard step == 1, let v = Int(base), range.contains(v) else { return nil }
                lo = v
                hi = v
            }

            var v = lo
            while v <= hi {
                values.insert(normalize?(v) ?? v)
                v += step
            }
        }
        guard !values.isEmpty else { return nil }
        return Field(values: values, sorted: values.sorted(), isWildcard: text == "*")
    }

    // MARK: - 匹配

    /// 给定时间点是否命中（精确到分钟；秒的取值不影响判定）。
    func matches(_ date: Date, calendar: Calendar = .current) -> Bool {
        let c = calendar.dateComponents([.minute, .hour, .day, .month, .weekday], from: date)
        guard let m = c.minute, let h = c.hour, let dom = c.day,
              let month = c.month, let weekday = c.weekday else { return false }
        return minute.contains(m) && hour.contains(h)
            && self.month.contains(month) && dayMatches(dom: dom, weekday: weekday)
    }

    /// 日/周并存判定：两字段都受限时任一命中即可（Vixie cron 语义），否则都要命中。
    /// - Parameter weekday: Calendar 的 weekday（1 = 周日 … 7 = 周六）。
    private func dayMatches(dom: Int, weekday: Int) -> Bool {
        let cronWeekday = weekday - 1   // 转成 cron 的 0-6（0 = 周日）
        let domHit = dayOfMonth.contains(dom)
        let dowHit = dayOfWeek.contains(cronWeekday)
        if dayOfMonth.isWildcard || dayOfWeek.isWildcard {
            return domHit && dowHit
        }
        return domHit || dowHit
    }

    // MARK: - next-fire

    /// date 之后（严格晚于）的下一个触发时间；找不到（如 "0 0 30 2 *" 永不命中）返回 nil。
    /// 逐天扫描，上限 5 年——足以覆盖 2 月 29 日这类四年一遇的条目。
    func nextFire(after date: Date, calendar: Calendar = .current) -> Date? {
        // 起点：date 所在分钟的下一分钟（floor 到整分钟再 +60s，保证严格晚于 date）
        let startComps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        guard let minuteFloor = calendar.date(from: startComps) else { return nil }
        let startDate = minuteFloor.addingTimeInterval(60)
        let startDay = calendar.startOfDay(for: startDate)

        for dayOffset in 0..<(366 * 5) {
            guard let dayStart = calendar.date(byAdding: .day, value: dayOffset, to: startDay) else {
                return nil
            }
            let d = calendar.dateComponents([.day, .month, .weekday], from: dayStart)
            guard let dom = d.day, let month = d.month, let weekday = d.weekday else { continue }
            guard self.month.contains(month), dayMatches(dom: dom, weekday: weekday) else { continue }

            // 当天内按序找最早命中的 时:分；起始日需跳过 startDate 之前的时刻
            let isStartDay = (dayOffset == 0)
            let startH = isStartDay ? calendar.component(.hour, from: startDate) : 0
            let startM = isStartDay ? calendar.component(.minute, from: startDate) : 0
            for h in hour.sorted where h >= startH {
                for m in minute.sorted {
                    if h == startH && m < startM { continue }
                    var comps = calendar.dateComponents([.year, .month, .day], from: dayStart)
                    comps.hour = h
                    comps.minute = m
                    // DST 切换点的不存在时刻由 Calendar 解析到相邻有效时间，可接受
                    if let candidate = calendar.date(from: comps), candidate > date {
                        return candidate
                    }
                }
            }
        }
        return nil
    }
}
