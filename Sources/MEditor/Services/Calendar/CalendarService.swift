import EventKit
import Foundation

/// EventKit 日历访问封装，提供授权和事件查询功能。
/// 实现 CalendarServiceProtocol，可与其他日历服务在 CompositeCalendarService 中组合使用。
@MainActor
final class CalendarService: CalendarServiceProtocol {
    /// 默认实例；测试或需要隔离 store 的场景可直接 `CalendarService(store:)` 构造。
    /// nonisolated：实例引用不可变且类型 Sendable，允许非隔离上下文（如 EnvironmentKey 默认值）引用。
    nonisolated static let shared = CalendarService()

    /// 仅在 init 赋值一次、之后只读；nonisolated(unsafe) 允许 nonisolated init 写入。
    nonisolated(unsafe) private let store: EKEventStore

    /// 仅给 let 属性赋值，标 nonisolated 以便非隔离上下文（如 EnvironmentKey 默认值）构造/引用。
    nonisolated init(store: EKEventStore = EKEventStore()) {
        self.store = store
    }

    var authorizationStatus: EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    /// 请求日历访问权限，返回是否已授权。
    func requestAccess() async -> Bool {
        if #available(macOS 14.0, *) {
            return (try? await store.requestFullAccessToEvents()) ?? false
        } else {
            return await withCheckedContinuation { continuation in
                store.requestAccess(to: .event) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    /// 获取从今天起 days 天内的日程事件，按开始时间升序排列。
    func fetchEvents(days: Int = 7) -> [EKEvent] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        guard let end = cal.date(byAdding: .day, value: days, to: start) else { return [] }
        let pred = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: pred).sorted { $0.startDate < $1.startDate }
    }

    /// 获取指定日期范围内的事件。
    func fetchEvents(from start: Date, to end: Date, calendars: [EKCalendar]? = nil) -> [EKEvent] {
        let pred = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        return store.events(matching: pred).sorted { $0.startDate < $1.startDate }
    }

    /// 获取所有可写的日历列表。
    func writableCalendars() -> [EKCalendar] {
        store.calendars(for: .event).filter { $0.allowsContentModifications }
    }

    /// 所有日历（含只读）。
    func allCalendars() -> [EKCalendar] {
        store.calendars(for: .event)
    }

    /// 创建新事件。返回是否成功。
    @discardableResult
    func createEvent(
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool = false,
        calendar: EKCalendar? = nil,
        notes: String? = nil
    ) -> Bool {
        let event = EKEvent(eventStore: store)
        event.title   = title
        event.startDate = startDate
        event.endDate   = isAllDay ? startDate : endDate
        event.isAllDay  = isAllDay
        event.calendar  = calendar ?? store.defaultCalendarForNewEvents
        if let notes { event.notes = notes }
        do {
            try store.save(event, span: .thisEvent)
            return true
        } catch {
            return false
        }
    }

    /// 删除事件。
    @discardableResult
    func deleteEvent(_ event: EKEvent) -> Bool {
        do {
            try store.remove(event, span: .thisEvent)
            return true
        } catch { return false }
    }
}

// MARK: - CalendarServiceProtocol Conformance

extension CalendarService {

    var serviceName: String { "系统日历" }

    var isAvailable: Bool {
        get async {
            let status = authorizationStatus
            if status == .authorized || status == .fullAccess { return true }
            if status == .notDetermined { return await requestAccess() }
            return false
        }
    }

    /// 实现协议方法：返回统一日历事件模型。
    func fetchEvents(from start: Date, to end: Date) async throws -> [UnifiedCalendarEvent] {
        guard await isAvailable else { return [] }
        let ekEvents = fetchEvents(from: start, to: end, calendars: nil)
        return ekEvents.map { ev in
            UnifiedCalendarEvent(
                id:        ev.eventIdentifier ?? UUID().uuidString,
                title:     ev.title ?? "无标题",
                startDate: ev.startDate,
                endDate:   ev.endDate,
                isAllDay:  ev.isAllDay,
                location:  ev.location,
                notes:     ev.notes,
                source:    "system"
            )
        }
    }
}
