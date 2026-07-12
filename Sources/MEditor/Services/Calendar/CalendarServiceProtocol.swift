import Foundation

// MARK: - UnifiedCalendarEvent

/// 统一的日历事件模型，用于 UI 展示。
struct UnifiedCalendarEvent: Identifiable, Sendable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let location: String?
    let notes: String?
    /// 来源标识，用于 UI 差异化展示（"system" / ...）
    let source: String

    var duration: TimeInterval { endDate.timeIntervalSince(startDate) }

    var formattedTime: String {
        if isAllDay { return "全天" }
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return "\(fmt.string(from: startDate)) – \(fmt.string(from: endDate))"
    }
}

// MARK: - CalendarServiceProtocol

/// 日历服务抽象协议。
@MainActor
protocol CalendarServiceProtocol: AnyObject {

    /// 服务名称（用于 UI 标签和日志）
    var serviceName: String { get }

    /// 当前服务是否可用（授权通过）
    var isAvailable: Bool { get async }

    /// 获取指定时间范围内的事件
    func fetchEvents(from start: Date, to end: Date) async throws -> [UnifiedCalendarEvent]

    /// 获取今天起 `days` 天内的事件（快捷方法）
    func fetchEvents(days: Int) async -> [UnifiedCalendarEvent]
}

// MARK: - Default implementation

extension CalendarServiceProtocol {

    func fetchEvents(days: Int) async -> [UnifiedCalendarEvent] {
        let cal   = Calendar.current
        let start = cal.startOfDay(for: Date())
        guard let end = cal.date(byAdding: .day, value: days, to: start) else { return [] }
        return (try? await fetchEvents(from: start, to: end)) ?? []
    }
}
