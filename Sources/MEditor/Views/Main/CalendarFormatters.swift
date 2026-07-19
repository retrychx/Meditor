import Foundation

// MARK: - Cached Formatters

/// DateFormatter 创建昂贵，月视图单帧会触发几十次格式化，这里统一静态缓存（仅在 @MainActor 视图内使用）。
enum CalendarFmt {
    static let monthTitle: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy年 M月"; return f
    }()
    static let weekStart: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "M月d日"; return f
    }()
    static let weekEnd: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "d日"; return f
    }()
    static let dayHeader: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "M月d日 EEEE"; f.locale = .current; return f
    }()
    static let weekdayShort: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE"; f.locale = .current; return f
    }()
    static let weekdayFull: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEEE"; f.locale = .current; return f
    }()
    static let timeShort: DateFormatter = {
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none; return f
    }()
    static let dateMedium: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none; return f
    }()
    static let dateTimeMedium: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short; return f
    }()
}

// MARK: - Helpers

private extension DateFormatter {
    @discardableResult
    func apply(_ configure: (DateFormatter) -> Void) -> DateFormatter {
        configure(self)
        return self
    }
}
