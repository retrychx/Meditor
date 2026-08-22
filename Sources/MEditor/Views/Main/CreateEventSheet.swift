import EventKit
import SwiftUI

// MARK: - Create Event Sheet

@MainActor
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
    @Environment(\.calendarService) private var service

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
                Text(L("calendar.newEvent"))
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
                TextField(L("event.title"), text: $title)
                    .font(.system(size: 14))

                Toggle(L("calendar.allDay"), isOn: $isAllDay)

                if !isAllDay {
                    DatePicker(L("event.start"), selection: $startDate, displayedComponents: [.date, .hourAndMinute])
                    DatePicker(L("event.end"), selection: $endDate,   displayedComponents: [.date, .hourAndMinute])
                } else {
                    DatePicker(L("event.date"), selection: $startDate, displayedComponents: [.date])
                }

                if !calendars.isEmpty {
                    Picker(L("event.calendar"), selection: $selectedCalendar) {
                        ForEach(calendars.filter { $0.allowsContentModifications }, id: \.calendarIdentifier) { cal in
                            HStack {
                                Circle().fill(Color(cgColor: cal.cgColor)).frame(width: 8, height: 8)
                                Text(cal.title)
                            }
                            .tag(Optional(cal))
                        }
                    }
                }

                TextField(L("event.notes"), text: $notes, axis: .vertical)
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
                Button(L("common.cancel")) { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
                Button(L("common.add")) { save() }
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
            errorMessage = L("event.saveFailed")
            isSaving = false
        }
    }
}
