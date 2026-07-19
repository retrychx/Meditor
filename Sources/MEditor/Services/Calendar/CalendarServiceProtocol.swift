import EventKit
import Foundation
import SwiftUI

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

    /// 静态缓存的 HH:mm 格式化器（DateFormatter 创建昂贵，避免每次访问新建）
    private static let timeFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt
    }()

    var formattedTime: String {
        if isAllDay { return "全天" }
        return "\(Self.timeFormatter.string(from: startDate)) – \(Self.timeFormatter.string(from: endDate))"
    }
}

// MARK: - CalendarServiceProtocol

/// 日历服务抽象协议。视图只依赖此协议，便于测试注入 mock。
@MainActor
protocol CalendarServiceProtocol: AnyObject {

    /// 服务名称（用于 UI 标签和日志）
    var serviceName: String { get }

    /// 当前服务是否可用（授权通过）
    var isAvailable: Bool { get async }

    /// 获取指定时间范围内的事件
    func fetchEvents(from start: Date, to end: Date) async throws -> [UnifiedCalendarEvent]

    // MARK: EventKit 直接 API（日历视图使用）

    /// 请求日历访问权限，返回是否已授权。
    func requestAccess() async -> Bool

    /// 获取从今天起 days 天内的事件。
    func fetchEvents(days: Int) -> [EKEvent]

    /// 获取指定日期范围内的事件。
    func fetchEvents(from start: Date, to end: Date, calendars: [EKCalendar]?) -> [EKEvent]

    /// 所有日历（含只读）。
    func allCalendars() -> [EKCalendar]

    /// 创建新事件。返回是否成功。
    @discardableResult
    func createEvent(
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        calendar: EKCalendar?,
        notes: String?
    ) -> Bool

    /// 删除事件。
    @discardableResult
    func deleteEvent(_ event: EKEvent) -> Bool
}

// MARK: - SwiftUI Environment 注入

private struct CalendarServiceEnvironmentKey: EnvironmentKey {
    static let defaultValue: any CalendarServiceProtocol = CalendarService.shared
}

extension EnvironmentValues {
    /// 日历服务，默认 `.shared`；测试可在视图上游 `.environment(\.calendarService, mock)` 注入。
    var calendarService: any CalendarServiceProtocol {
        get { self[CalendarServiceEnvironmentKey.self] }
        set { self[CalendarServiceEnvironmentKey.self] = newValue }
    }
}
