import Foundation

// MARK: - UnifiedCalendarEvent

/// 统一的日历事件模型，抽象 EventKit EKEvent 和 InternalCalendarEvent 的差异。
/// 所有 CalendarService 实现都向此模型转换，上层视图只依赖此类型。
struct UnifiedCalendarEvent: Identifiable, Sendable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let location: String?
    let notes: String?
    /// 来源标识，用于 UI 差异化展示（"system" / "internal_calendar" / ...）
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
///
/// 设计原则：
///  - 上层组件（WeekTimelineView / CalendarSidebarView）只依赖此协议
///  - 系统日历（EventKit）和 InternalCalendar 日历均实现此协议
///  - #if INTERNAL_BUILD 控制 InternalCalendar 实现的编译
@MainActor
protocol CalendarServiceProtocol: AnyObject {

    /// 服务名称（用于 UI 标签和日志）
    var serviceName: String { get }

    /// 当前服务是否可用（授权通过 + 必要配置已填写）
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

// MARK: - CompositeCalendarService

/// 将多个 CalendarServiceProtocol 合并为一个，按优先级依次查询并合并结果。
/// 可用于同时显示系统日历 + InternalCalendar 日历（如有）。
@MainActor
final class CompositeCalendarService: CalendarServiceProtocol {

    let services: [any CalendarServiceProtocol]
    let serviceName: String = "综合日历"

    init(services: [any CalendarServiceProtocol]) {
        self.services = services
    }

    var isAvailable: Bool {
        get async {
            for service in services {
                if await service.isAvailable { return true }
            }
            return false
        }
    }

    func fetchEvents(from start: Date, to end: Date) async throws -> [UnifiedCalendarEvent] {
        var results: [UnifiedCalendarEvent] = []
        for service in services {
            guard await service.isAvailable else { continue }
            let events = (try? await service.fetchEvents(from: start, to: end)) ?? []
            results.append(contentsOf: events)
        }
        // 按开始时间排序，去重（相同 id）
        var seen = Set<String>()
        return results
            .sorted { $0.startDate < $1.startDate }
            .filter { seen.insert($0.id).inserted }
    }
}
