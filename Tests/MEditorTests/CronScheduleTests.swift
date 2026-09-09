import XCTest
@testable import MEditor

// MARK: - CronScheduleTests
//
// cron 解析与 next-fire 计算（定时任务的单测重点）：
//   解析：* / 具体值 / 列表 / 范围 / *​/n 与范围步进 / 周字段 7→周日 / 各类非法表达式
//   next-fire：每分钟、每天定点、工作日、月初、月末缺失日（2/31）、闰年 2/29、跨年、
//              日周并存 OR 语义、永不命中返回 nil
//
// 测试统一用固定 UTC Calendar（格里历），避免 CI 机器时区影响。
// DST（夏令时）不在保证范围内：行为约定见 CronSchedule 头注释（不存在时刻由
// Calendar 解析到相邻有效时间，重复小时不重复触发），这里不做断言。

final class CronScheduleTests: XCTestCase {

    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar = cal
    }

    /// 构造 UTC 日期
    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: mo, day: d,
                                           hour: h, minute: mi, second: s))!
    }

    // MARK: - 解析：合法表达式

    func test_parse_wildcard_allFieldsFullRange() {
        let s = CronSchedule.parse("* * * * *")
        XCTAssertNotNil(s)
        XCTAssertEqual(s?.minute.values.count, 60)
        XCTAssertEqual(s?.hour.values.count, 24)
        XCTAssertEqual(s?.dayOfMonth.values.count, 31)
        XCTAssertEqual(s?.month.values.count, 12)
        XCTAssertEqual(s?.dayOfWeek.values.count, 7)
        XCTAssertTrue(s?.minute.isWildcard == true)
    }

    func test_parse_specificValues() {
        let s = CronSchedule.parse("30 9 15 6 2")
        XCTAssertEqual(s?.minute.values, [30])
        XCTAssertEqual(s?.hour.values, [9])
        XCTAssertEqual(s?.dayOfMonth.values, [15])
        XCTAssertEqual(s?.month.values, [6])
        XCTAssertEqual(s?.dayOfWeek.values, [2])
        XCTAssertFalse(s?.dayOfMonth.isWildcard ?? true)
    }

    func test_parse_list() {
        let s = CronSchedule.parse("0,30 9,18 * * *")
        XCTAssertEqual(s?.minute.values, [0, 30])
        XCTAssertEqual(s?.hour.values, [9, 18])
    }

    func test_parse_range() {
        let s = CronSchedule.parse("0 9 * * 1-5")
        XCTAssertEqual(s?.dayOfWeek.values, [1, 2, 3, 4, 5])
    }

    func test_parse_stepStar() {
        let s = CronSchedule.parse("*/15 * * * *")
        XCTAssertEqual(s?.minute.values, [0, 15, 30, 45])
    }

    func test_parse_rangeStep() {
        let s = CronSchedule.parse("0 9-17/2 * * *")
        XCTAssertEqual(s?.hour.values, [9, 11, 13, 15, 17])
    }

    func test_parse_combinedListRangeStep() {
        let s = CronSchedule.parse("5,10-20/5,55 * * * *")
        XCTAssertEqual(s?.minute.values, [5, 10, 15, 20, 55])
    }

    func test_parse_weekdaySevenIsSunday() {
        // 兼容常见写法：7 = 周日（与 0 等价）
        let s = CronSchedule.parse("0 9 * * 0,7")
        XCTAssertEqual(s?.dayOfWeek.values, [0])
    }

    func test_parse_stepOverSundayRange() {
        // 0-7 归一化后 {0..6}
        let s = CronSchedule.parse("0 0 * * 0-7")
        XCTAssertEqual(s?.dayOfWeek.values, Set(0...6))
    }

    // MARK: - 解析：非法表达式

    func test_parse_invalidExpressions() {
        let invalid = [
            "",                     // 空
            "* * * *",              // 少一字段
            "* * * * * *",          // 多一字段
            "60 * * * *",           // 分钟超界
            "* 24 * * *",           // 小时超界
            "* * 0 * *",            // 日超界
            "* * * 13 *",           // 月超界
            "* * * * 8",            // 周超界
            "*/0 * * * *",          // 步进 0
            "*/-1 * * * *",         // 负步进
            "5-1 * * * *",          // 范围倒置
            "abc * * * *",          // 非数字
            "1, * * * *",           // 空 token
            "1- * * * *",           // 缺范围上界
            "5/2 * * * *",          // 单值不支持步进
            "0 9 * * 1-5/0",        // 范围步进 0
        ]
        for expr in invalid {
            XCTAssertNil(CronSchedule.parse(expr), "应拒绝非法表达式：\(expr)")
        }
    }

    // MARK: - next-fire：基础

    func test_nextFire_everyMinute_isNextMinuteBoundary() {
        let s = CronSchedule.parse("* * * * *")!
        let next = s.nextFire(after: date(2024, 1, 15, 10, 30, 45), calendar: calendar)
        XCTAssertEqual(next, date(2024, 1, 15, 10, 31, 0))
    }

    func test_nextFire_everyMinute_exactMinuteBoundaryGoesToNext() {
        // 严格晚于 after：刚好整分钟时取下一分钟
        let s = CronSchedule.parse("* * * * *")!
        let next = s.nextFire(after: date(2024, 1, 15, 10, 30, 0), calendar: calendar)
        XCTAssertEqual(next, date(2024, 1, 15, 10, 31, 0))
    }

    func test_nextFire_dailyAt9_sameDayWhenBefore() {
        let s = CronSchedule.parse("0 9 * * *")!
        XCTAssertEqual(s.nextFire(after: date(2024, 1, 15, 8, 59, 30), calendar: calendar),
                       date(2024, 1, 15, 9, 0))
    }

    func test_nextFire_dailyAt9_nextDayWhenPast() {
        let s = CronSchedule.parse("0 9 * * *")!
        XCTAssertEqual(s.nextFire(after: date(2024, 1, 15, 9, 0, 30), calendar: calendar),
                       date(2024, 1, 16, 9, 0))
    }

    // MARK: - next-fire：工作日 / 月 / 边界

    func test_nextFire_weekdays_skipsWeekend() {
        // 2024-01-12 是周五；09:00 已过的下一个工作日触发 = 周一 01-15 09:00
        let s = CronSchedule.parse("0 9 * * 1-5")!
        XCTAssertEqual(s.nextFire(after: date(2024, 1, 12, 9, 0, 1), calendar: calendar),
                       date(2024, 1, 15, 9, 0))
    }

    func test_nextFire_firstOfMonth() {
        let s = CronSchedule.parse("30 8 1 * *")!
        XCTAssertEqual(s.nextFire(after: date(2024, 1, 15, 12, 0), calendar: calendar),
                       date(2024, 2, 1, 8, 30))
    }

    func test_nextFire_day31_skipsShortMonths() {
        // 2 月没有 31 号 → 跳到 3 月 31 日
        let s = CronSchedule.parse("0 0 31 * *")!
        XCTAssertEqual(s.nextFire(after: date(2024, 2, 1, 0, 0), calendar: calendar),
                       date(2024, 3, 31, 0, 0))
    }

    func test_nextFire_leapDay() {
        // 2024-02-29 已过后，下一次 2/29 是 2028（2025-2027 非闰年）
        let s = CronSchedule.parse("0 0 29 2 *")!
        XCTAssertEqual(s.nextFire(after: date(2025, 3, 1, 0, 0), calendar: calendar),
                       date(2028, 2, 29, 0, 0))
    }

    func test_nextFire_yearCrossing() {
        let s = CronSchedule.parse("0 0 1 1 *")!
        XCTAssertEqual(s.nextFire(after: date(2024, 12, 31, 23, 59, 30), calendar: calendar),
                       date(2025, 1, 1, 0, 0))
    }

    func test_nextFire_dayOfMonthOrWeekday_vixieOrSemantics() {
        // 「日」与「周」都受限时任一命中：每月 15 号或每周一
        // 2024-01-16（周二）之后，下个周一 01-22 先命中（虽然 22 不是 15 号）
        let s = CronSchedule.parse("0 9 15 * 1")!
        XCTAssertEqual(s.nextFire(after: date(2024, 1, 16, 0, 0), calendar: calendar),
                       date(2024, 1, 22, 9, 0))
        // 周一 01-22 已过后，下一个周一 01-29 命中（OR 语义，等不到 15 号）
        XCTAssertEqual(s.nextFire(after: date(2024, 1, 22, 9, 0, 1), calendar: calendar),
                       date(2024, 1, 29, 9, 0))
        // 周一 02-12 已过后，02-15（周四，15 号）命中
        XCTAssertEqual(s.nextFire(after: date(2024, 2, 12, 9, 0, 1), calendar: calendar),
                       date(2024, 2, 15, 9, 0))
    }

    func test_nextFire_neverMatchingExpression_returnsNil() {
        // 2 月 30 日永远不存在 → 扫满 5 年后返回 nil（而不是死循环）
        let s = CronSchedule.parse("0 0 30 2 *")!
        XCTAssertNil(s.nextFire(after: date(2024, 1, 1, 0, 0), calendar: calendar))
    }

    // MARK: - matches

    func test_matches_basic() {
        let s = CronSchedule.parse("0 9 * * 1-5")!
        XCTAssertTrue(s.matches(date(2024, 1, 15, 9, 0, 30), calendar: calendar),   // 周一 09:00
                      "秒不影响分钟级匹配")
        XCTAssertFalse(s.matches(date(2024, 1, 15, 9, 1), calendar: calendar))
        XCTAssertFalse(s.matches(date(2024, 1, 14, 9, 0), calendar: calendar))      // 周日
    }

    func test_matches_monthAndDayAnd() {
        // 周为 * 时与日取 AND：2 月 29 日
        let s = CronSchedule.parse("0 0 29 2 *")!
        XCTAssertTrue(s.matches(date(2024, 2, 29, 0, 0), calendar: calendar))
        XCTAssertFalse(s.matches(date(2024, 3, 29, 0, 0), calendar: calendar))
    }
}
