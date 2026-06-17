import SwiftUI

/// Small custom input dialog used for create / rename flows.
///
/// macOS system `.alert` default-button color is driven by the OS-wide
/// `NSColor.controlAccentColor` and cannot be retinted by SwiftUI, so these
/// flows use this in-app dialog instead — its confirm button honors the app's
/// accent-style preference (`Color.appAccent`) like the rest of the UI.
struct InputDialog: View {
    let title: String
    let message: String
    let placeholder: String
    let confirmTitle: String
    @Binding var text: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @FocusState private var focused: Bool

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: DS.Space.lg) {
            VStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit { if !trimmed.isEmpty { onConfirm() } }

            HStack(spacing: DS.Space.sm) {
                Button(L("common.cancel"), action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(confirmTitle, action: onConfirm)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(Color.appAccent)
                    .disabled(trimmed.isEmpty)
            }
        }
        .padding(DS.Space.xl)
        .frame(width: 320)
        .onAppear { DispatchQueue.main.async { focused = true } }
    }
}
