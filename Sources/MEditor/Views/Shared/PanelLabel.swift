import SwiftUI

struct PanelLabel: View {
    let title: String
    let icon: String

    init(_ title: String, icon: String) {
        self.title = title
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .default))
                .foregroundStyle(.tertiary)
                .tracking(0.5)
            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(height: 30)
        .background(.ultraThinMaterial)
    }
}
