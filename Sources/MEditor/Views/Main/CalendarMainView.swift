import EventKit
import SwiftUI

// MARK: - View Mode

private enum CalendarViewMode: String, CaseIterable {
    case month = "月"
    case week  = "周"
}

// MARK: - CalendarMainView

/// 全宽日历主视图：月视图/周视图、导航、创建事件、事件详情。
struct CalendarMainView: View {
    @State private var viewMode: CalendarViewMode = .month
    @State private var referenceDate: Date = Date()
    @State private var events: [EKEvent] = []
    @State private var authStatus: EKAuthorizationStatus = .notDetermined
    @State private var isLoading = false
    @State private var selectedDate: Date? = nil
    @State private var selectedEvent: EKEvent? = nil
    @State private var showCreateSheet = false
    @State private var createForDate: Date? = nil
    @State private var calendarFilter: Set<String> = []     // empty = all
    @State private var allCalendars: [EKCalendar] = []

    private let service = CalendarService.shared

    // Visible range for the current view
    private var visibleRange: (Date, Date) {
        let cal = Calendar.current
        switch viewMode {
        case .month:
            let comps = cal.dateComponents([.year, .month], from: referenceDate)
            let first = cal.date(from: comps)!
            let last  = cal.date(byAdding: DateComponents(month: 1, day: -1), to: first)!
            // Extend to grid edges (Mon..Sun)
            let gridStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: first))!
            let gridEnd   = cal.date(byAdding: .day, value: 42, to: gridStart)!
            return (gridStart, gridEnd)
        case .week:
            let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: referenceDate))!
            let weekEnd   = cal.date(byAdding: .day, value: 7, to: weekStart)!
            return (weekStart, weekEnd)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().opacity(0.3)

            if authStatus != .fullAccess {
                unauthorizedView
            } else {
                Group {
                    switch viewMode {
                    case .month: monthGrid
                    case .week:  weekList
                    }
                }
            }
        }
        .task { await load() }
        .onChange(of: referenceDate) { _, _ in Task { await reload() } }
        .onChange(of: viewMode)      { _, _ in Task { await reload() } }
        .sheet(isPresented: $showCreateSheet, onDismiss: { Task { await reload() } }) {
            CreateEventSheet(defaultDate: createForDate ?? Date(), calendars: allCalendars)
        }
        .popover(item: $selectedEvent, arrowEdge: .trailing) { event in
            EventDetailPopover(event: event) {
                selectedEvent = nil
                Task { await reload() }
            }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            // 日历颜色图标
            Image(systemName: "calendar")
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.appAccent)

            Text(navigationTitle)
                .font(.system(size: 16, weight: .semibold))
                .frame(minWidth: 140, alignment: .leading)

            Spacer()

            // 今天
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { referenceDate = Date() }
            } label: {
                Text("今天")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())
            }
            .buttonStyle(.plain)

            // 上一页
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { navigate(by: -1) }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.plain)

            // 下一页
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { navigate(by: 1) }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.plain)

            Divider().frame(height: 16)

            // 视图切换
            Picker("", selection: $viewMode) {
                ForEach(CalendarViewMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 80)

            // 新建事件
            Button {
                createForDate = nil
                showCreateSheet = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.appAccent)
            }
            .buttonStyle(.plain)
            .help("新建事件")

            if isLoading {
                ProgressView().controlSize(.small)
            } else {
                Button { Task { await reload() } } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("刷新")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var navigationTitle: String {
        let fmt = DateFormatter()
        switch viewMode {
        case .month:
            fmt.dateFormat = "yyyy年 M月"
        case .week:
            let (s, e) = visibleRange
            let sf = DateFormatter(); sf.dateFormat = "M月d日"
            let ef = DateFormatter(); ef.dateFormat = "d日"
            return "\(sf.string(from: s)) – \(ef.string(from: Calendar.current.date(byAdding: .day, value: -1, to: e)!))"
        }
        return fmt.string(from: referenceDate)
    }

    // MARK: - Month Grid

    private var monthGrid: some View {
        let cal = Calendar.current
        let (gridStart, _) = visibleRange
        let days = (0..<42).compactMap { cal.date(byAdding: .day, value: $0, to: gridStart) }
        let currentMonth = cal.component(.month, from: referenceDate)

        return VStack(spacing: 0) {
            // Day-of-week header
            HStack(spacing: 0) {
                ForEach(["日","一","二","三","四","五","六"], id: \.self) { d in
                    Text(d)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
            }
            Divider().opacity(0.3)

            // Grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
                ForEach(days, id: \.self) { day in
                    MonthDayCell(
                        date: day,
                        isCurrentMonth: cal.component(.month, from: day) == currentMonth,
                        isToday: cal.isDateInToday(day),
                        isSelected: selectedDate.map { cal.isDate($0, inSameDayAs: day) } ?? false,
                        events: eventsOn(day)
                    )
                    .onTapGesture {
                        selectedDate = day
                    }
                    .contextMenu {
                        Button("新建事件") {
                            createForDate = day
                            showCreateSheet = true
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        // Show events list when day is selected
                        EmptyView()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Selected day events
            if let sel = selectedDate {
                Divider().opacity(0.3)
                selectedDayEvents(for: sel)
                    .frame(height: 140)
            }
        }
    }

    // MARK: - Selected Day Events Panel

    private func selectedDayEvents(for date: Date) -> some View {
        let dayEvents = eventsOn(date)
        let fmt = DateFormatter()
        fmt.dateFormat = "M月d日 EEEE"
        fmt.locale = Locale.current
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(fmt.string(from: date))
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
                Spacer()
                Button {
                    createForDate = date
                    showCreateSheet = true
                } label: {
                    Label("新建", systemImage: "plus")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.appAccent)
                .padding(.trailing, 16)
                .padding(.top, 10)
            }
            if dayEvents.isEmpty {
                Text("无事件")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 16)
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 2) {
                        ForEach(dayEvents, id: \.eventIdentifier) { event in
                            EventRow(event: event)
                                .onTapGesture { selectedEvent = event }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }
            }
        }
        .background(Color.primary.opacity(0.02))
    }

    // MARK: - Week List

    private var weekList: some View {
        let cal = Calendar.current
        let (start, end) = visibleRange
        let days = stride(from: start, to: end, by: 86400).map { Date(timeIntervalSinceReferenceDate: $0.timeIntervalSinceReferenceDate) }

        return ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(days, id: \.self) { day in
                    WeekDaySection(
                        date: day,
                        events: eventsOn(day),
                        onSelectEvent: { selectedEvent = $0 },
                        onCreateEvent: {
                            createForDate = day
                            showCreateSheet = true
                        }
                    )
                    Divider().opacity(0.15)
                }
            }
            .padding(.bottom, 20)
        }
    }

    // MARK: - Unauthorized

    private var unauthorizedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tertiary)
            Text(L("calendar.accessHint"))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(L("calendar.requestAccess")) {
                Task {
                    let granted = await service.requestAccess()
                    authStatus = EKEventStore.authorizationStatus(for: .event)
                    if granted { await reload() }
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.appAccent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 48)
    }

    // MARK: - Helpers

    private func eventsOn(_ date: Date) -> [EKEvent] {
        let cal = Calendar.current
        return events.filter { event in
            let start = event.startDate!
            let end   = event.endDate!
            let dayStart = cal.startOfDay(for: date)
            let dayEnd   = cal.date(byAdding: .day, value: 1, to: dayStart)!
            return start < dayEnd && end > dayStart
        }
    }

    private func navigate(by delta: Int) {
        let cal = Calendar.current
        switch viewMode {
        case .month:
            referenceDate = cal.date(byAdding: .month, value: delta, to: referenceDate) ?? referenceDate
        case .week:
            referenceDate = cal.date(byAdding: .weekOfYear, value: delta, to: referenceDate) ?? referenceDate
        }
    }

    private func load() async {
        authStatus = EKEventStore.authorizationStatus(for: .event)
        allCalendars = service.allCalendars()
        if authStatus == .fullAccess { await reload() }
    }

    private func reload() async {
        guard authStatus == .fullAccess else { return }
        isLoading = true
        let (s, e) = visibleRange
        events = service.fetchEvents(from: s, to: e)
        isLoading = false
    }
}

// MARK: - Month Day Cell

private struct MonthDayCell: View {
    let date: Date
    let isCurrentMonth: Bool
    let isToday: Bool
    let isSelected: Bool
    let events: [EKEvent]
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Day number
            HStack {
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.system(size: 13, weight: isToday ? .bold : .regular))
                    .foregroundStyle(
                        isToday ? Color.white :
                        isCurrentMonth ? Color.primary : Color.secondary.opacity(0.5)
                    )
                    .frame(width: 24, height: 24)
                    .background {
                        if isToday {
                            Circle().fill(Color.appAccent)
                        } else if isSelected {
                            Circle().fill(Color.appAccent.opacity(0.15))
                        }
                    }
                Spacer()
            }
            .padding(.top, 4)
            .padding(.horizontal, 4)

            // Event dots / pills
            VStack(alignment: .leading, spacing: 2) {
                ForEach(events.prefix(3), id: \.eventIdentifier) { event in
                    EventPill(event: event, compact: true)
                }
                if events.count > 3 {
                    Text("+\(events.count - 3) 个")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, 2)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 80, maxHeight: .infinity)
        .background(
            isSelected ? Color.appAccent.opacity(0.06) :
            isHovered  ? Color.primary.opacity(0.03) : Color.clear
        )
        .overlay(
            Rectangle()
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .animation(DS.Motion.micro, value: isHovered)
    }
}

// MARK: - Event Pill

private struct EventPill: View {
    let event: EKEvent
    let compact: Bool

    var body: some View {
        HStack(spacing: 3) {
            if !compact {
                Circle()
                    .fill(Color(cgColor: event.calendar.cgColor))
                    .frame(width: 6, height: 6)
            }
            Text(event.title ?? "（无标题）")
                .font(.system(size: compact ? 9.5 : 12))
                .foregroundStyle(compact ? Color.white : Color.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, compact ? 4 : 8)
        .padding(.vertical, compact ? 1.5 : 3)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color(cgColor: event.calendar.cgColor).opacity(compact ? 0.85 : 0.15))
        )
    }
}

// MARK: - Week Day Section

private struct WeekDaySection: View {
    let date: Date
    let events: [EKEvent]
    let onSelectEvent: (EKEvent) -> Void
    let onCreateEvent: () -> Void

    private var isToday: Bool { Calendar.current.isDateInToday(date) }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Date column
            VStack(spacing: 2) {
                Text(dayOfWeekLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isToday ? Color.appAccent : .secondary)
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.system(size: 22, weight: isToday ? .bold : .light))
                    .foregroundStyle(isToday ? Color.appAccent : .primary)
            }
            .frame(width: 52)
            .padding(.top, 12)
            .padding(.bottom, 12)

            Divider().padding(.vertical, 8)

            // Events column
            VStack(alignment: .leading, spacing: 4) {
                if events.isEmpty {
                    Text("无事件")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(events, id: \.eventIdentifier) { event in
                        EventRow(event: event)
                            .onTapGesture { onSelectEvent(event) }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Add button (on hover)
            Button {
                onCreateEvent()
            } label: {
                Image(systemName: "plus.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.appAccent.opacity(0.6))
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
            .padding(.trailing, 12)
        }
    }

    private var dayOfWeekLabel: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEE"
        fmt.locale = Locale.current
        return fmt.string(from: date)
    }
}

// MARK: - Event Row

private struct EventRow: View {
    let event: EKEvent
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(Color(cgColor: event.calendar.cgColor))
                .frame(width: 3)
                .cornerRadius(2)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title ?? "（无标题）")
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(timeLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let notes = event.notes, !notes.isEmpty {
                Image(systemName: "note.text")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isHovered ? Color.primary.opacity(0.04) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous))
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

// MARK: - Event Detail Popover

private struct EventDetailPopover: View {
    let event: EKEvent
    let onDismiss: () -> Void
    @State private var showDeleteConfirm = false
    private let service = CalendarService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title ?? "（无标题）")
                        .font(.system(size: 15, weight: .semibold))
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color(cgColor: event.calendar.cgColor))
                            .frame(width: 8, height: 8)
                        Text(event.calendar.title)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button { onDismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            Divider()

            // Details
            VStack(alignment: .leading, spacing: 10) {
                detailRow(icon: "clock", text: timeText)
                if let location = event.location, !location.isEmpty {
                    detailRow(icon: "mappin", text: location)
                }
                if let notes = event.notes, !notes.isEmpty {
                    detailRow(icon: "note.text", text: notes)
                }
            }
            .padding(16)

            // Actions
            if event.calendar.allowsContentModifications {
                Divider()
                HStack {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("删除", systemImage: "trash")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .confirmationDialog("确认删除此事件？", isPresented: $showDeleteConfirm) {
                        Button("删除", role: .destructive) {
                            service.deleteEvent(event)
                            onDismiss()
                        }
                        Button("取消", role: .cancel) {}
                    }
                    Spacer()
                    Button {
                        // 在系统日历中打开
                        if let url = URL(string: "ical://") { NSWorkspace.shared.open(url) }
                    } label: {
                        Label("在日历中查看", systemImage: "arrow.up.right.square")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.appAccent)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
        .frame(width: 300)
    }

    private func detailRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
        }
    }

    private var timeText: String {
        if event.isAllDay {
            let fmt = DateFormatter(); fmt.dateStyle = .medium; fmt.timeStyle = .none
            return fmt.string(from: event.startDate)
        }
        let fmt = DateFormatter(); fmt.dateStyle = .medium; fmt.timeStyle = .short
        return "\(fmt.string(from: event.startDate)) – \(DateFormatter().apply { $0.timeStyle = .short; $0.dateStyle = .none }.string(from: event.endDate))"
    }
}

// MARK: - Create Event Sheet

struct CreateEventSheet: View {
    let defaultDate: Date
    let calendars: [EKCalendar]
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var isAllDay = false
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var selectedCalendar: EKCalendar?
    @State private var notes = ""
    @State private var isSaving = false
    @State private var errorMessage: String? = nil
    private let service = CalendarService.shared

    init(defaultDate: Date, calendars: [EKCalendar]) {
        self.defaultDate = defaultDate
        self.calendars = calendars
        let cal = Calendar.current
        let start = cal.date(bySettingHour: 9, minute: 0, second: 0, of: defaultDate) ?? defaultDate
        let end   = cal.date(byAdding: .hour, value: 1, to: start) ?? start
        _startDate = State(initialValue: start)
        _endDate   = State(initialValue: end)
        _selectedCalendar = State(initialValue: calendars.first(where: { $0.allowsContentModifications }))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("新建事件")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(6)
                        .background(Circle().fill(.quaternary))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            // Form
            Form {
                TextField("标题", text: $title)
                    .font(.system(size: 14))

                Toggle("全天", isOn: $isAllDay)

                if !isAllDay {
                    DatePicker("开始", selection: $startDate, displayedComponents: [.date, .hourAndMinute])
                    DatePicker("结束", selection: $endDate,   displayedComponents: [.date, .hourAndMinute])
                } else {
                    DatePicker("日期", selection: $startDate, displayedComponents: [.date])
                }

                if !calendars.isEmpty {
                    Picker("日历", selection: $selectedCalendar) {
                        ForEach(calendars.filter { $0.allowsContentModifications }, id: \.calendarIdentifier) { cal in
                            HStack {
                                Circle().fill(Color(cgColor: cal.cgColor)).frame(width: 8, height: 8)
                                Text(cal.title)
                            }
                            .tag(Optional(cal))
                        }
                    }
                }

                TextField("备注", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
                    .font(.system(size: 13))
            }
            .formStyle(.grouped)

            if let err = errorMessage {
                Text(err)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 20)
            }

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
                Button("添加") { save() }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.appAccent)
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 380)
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty else { return }
        isSaving = true
        let success = service.createEvent(
            title: trimmedTitle,
            startDate: startDate,
            endDate: isAllDay ? startDate : endDate,
            isAllDay: isAllDay,
            calendar: selectedCalendar,
            notes: notes.isEmpty ? nil : notes
        )
        if success {
            dismiss()
        } else {
            errorMessage = "保存失败，请检查日历权限"
            isSaving = false
        }
    }
}

// MARK: - Helpers

private extension DateFormatter {
    @discardableResult
    func apply(_ configure: (DateFormatter) -> Void) -> DateFormatter {
        configure(self)
        return self
    }
}

extension EKEvent: @retroactive Identifiable {
    public var id: String { eventIdentifier ?? UUID().uuidString }
}
