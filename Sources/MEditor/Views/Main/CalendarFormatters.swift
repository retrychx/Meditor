import Foundation

// MARK: - Cached Formatters

/// DateFormatter 创建昂贵，月视图单帧会触发几十次格式化，这里统一静态缓存（仅在 @MainActor 视图内使用）。
/// 日期格式本身已本地化（跟随应用内语言），按语言分桶缓存，切换语言后自动生效。
enum CalendarFmt {
    private static var cache: [String: DateFormatter] = [:]

    private static var appLocale: Locale {
        Locale(identifier: LocalizationManager.shared.resolved == .chinese ? "zh_CN" : "en_US")
    }

    private static func cached(_ key: String, _ make: (DateFormatter) -> Void) -> DateFormatter {
        let cacheKey = "\(LocalizationManager.shared.resolved.rawValue).\(key)"
        if let f = cache[cacheKey] { return f }
        let f = DateFormatter()
        make(f)
        cache[cacheKey] = f
        return f
    }

    static var monthTitle: DateFormatter { cached("monthTitle") { $0.locale = appLocale; $0.dateFormat = L("calendar.fmt.monthTitle") } }
    static var weekStart: DateFormatter { cached("weekStart") { $0.locale = appLocale; $0.dateFormat = L("calendar.fmt.weekStart") } }
    static var weekEnd: DateFormatter { cached("weekEnd") { $0.locale = appLocale; $0.dateFormat = L("calendar.fmt.weekEnd") } }
    static var dayHeader: DateFormatter { cached("dayHeader") { $0.locale = appLocale; $0.dateFormat = L("calendar.fmt.dayHeader") } }
    static var weekdayShort: DateFormatter { cached("weekdayShort") { $0.locale = appLocale; $0.dateFormat = "EEE" } }
    static var weekdayFull: DateFormatter { cached("weekdayFull") { $0.locale = appLocale; $0.dateFormat = "EEEE" } }
    /// 周日开头的超短星期标题（跟随应用内语言），用于月视图列头。
    static var veryShortWeekdaySymbols: [String] {
        cached("weekdayVeryShort") { $0.locale = appLocale }.veryShortWeekdaySymbols
    }
    static var timeShort: DateFormatter { cached("timeShort") { $0.timeStyle = .short; $0.dateStyle = .none } }
    static var dateMedium: DateFormatter { cached("dateMedium") { $0.dateStyle = .medium; $0.timeStyle = .none } }
    static var dateTimeMedium: DateFormatter { cached("dateTimeMedium") { $0.dateStyle = .medium; $0.timeStyle = .short } }
}

// MARK: - Helpers

private extension DateFormatter {
    @discardableResult
    func apply(_ configure: (DateFormatter) -> Void) -> DateFormatter {
        configure(self)
        return self
    }
}
