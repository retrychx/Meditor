import EventKit
import SwiftUI

/// 全宽日历主视图 — 点击底部 tab 的"日历"后替换主内容区。
struct CalendarMainView: View {
    @State private var events: [EKEvent] = []
    @State private var authStatus: EKAuthorizationStatus = .notDetermined
    @State private var isLoading = false

    private let service = CalendarService.shared

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider().opacity(0.3)
            content
        }
        .task {
            await loadIfAuthorized()
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar")
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.appAccent)

            Text(L("sidebar.calendar"))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer()

            if isLoading {
                ProgressView().controlSize(.small)
            } else if authStatus == .fullAccess {
                Button {
                    Task { await refreshEvents() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("刷新日历")
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        let isAuthorized = (authStatus == .fullAccess)

        if !isAuthorized {
            unauthorizedView
        } else if events.isEmpty && !isLoading {
            emptyView
        } else {
            eventList
        }
    }

    private var unauthorizedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.tertiary)
            Text(L("calendar.accessHint"))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(L("calendar.requestAccess")) {
                Task {
                    let granted = await service.requestAccess()
                    authStatus = EKEventStore.authorizationStatus(for: .event)
                    if granted { await refreshEvents() }
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .tint(Color.appAccent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 48)
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.tertiary)
            Text(L("calendar.empty"))
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var eventList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(groupedEvents, id: \.0) { (dateKey, dayEvents) in
                    Section {
                        LazyVStack(spacing: 0) {
                            ForEach(dayEvents, id: \.eventIdentifier) { event in
                                CalendarMainEventRow(event: event)
                            }
                        }
                    } header: {
                        Text(sectionTitle(for: dateKey))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .kerning(0.2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 24)
                            .padding(.top, 16)
                            .padding(.bottom, 4)
                    }
                }
            }
            .padding(.bottom, 20)
        }
    }

    // MARK: - Helpers

    private var groupedEvents: [(String, [EKEvent])] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        var dict: [(String, [EKEvent])] = []
        var seen: [String: Int] = [:]
        for event in events {
            let key = formatter.string(from: event.startDate)
            if let idx = seen[key] {
                dict[idx].1.append(event)
            } else {
                seen[key] = dict.count
                dict.append((key, [event]))
            }
        }
        return dict
    }

    private func sectionTitle(for dateKey: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateKey) else { return dateKey }
        let cal = Calendar.current
        if cal.isDateInToday(date) { return L("calendar.today") }
        if cal.isDateInTomorrow(date) { return L("calendar.tomorrow") }
        let display = DateFormatter()
        display.dateFormat = "M月d日 EEEE"
        display.locale = Locale.current
        return display.string(from: date)
    }

    private func loadIfAuthorized() async {
        authStatus = EKEventStore.authorizationStatus(for: .event)
        if authStatus == .fullAccess {
            await refreshEvents()
        }
    }

    private func refreshEvents() async {
        isLoading = true
        events = service.fetchEvents(days: 7)
        isLoading = false
    }
}

// MARK: - Event Row

private struct CalendarMainEventRow: View {
    let event: EKEvent
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(Color(cgColor: event.calendar.cgColor))
                .frame(width: 9, height: 9)

            VStack(alignment: .leading, spacing: 3) {
                Text(event.title ?? "（无标题）")
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(timeLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .background(
            isHovered ? Color.primary.opacity(0.04) : Color.clear
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .animation(DS.Motion.micro, value: isHovered)
    }

    private var timeLabel: String {
        if event.isAllDay { return L("calendar.allDay") }
        let fmt = DateFormatter()
        fmt.timeStyle = .short
        fmt.dateStyle = .none
        return "\(fmt.string(from: event.startDate)) – \(fmt.string(from: event.endDate))"
    }
}
