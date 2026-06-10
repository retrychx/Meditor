import SwiftUI

/// A left-side outline showing document headings for quick navigation.
struct TOCOutlineView: View {
    let items: [TOCItem]
    let theme: PreviewTheme
    let activeLineIndex: Int
    let isLoading: Bool
    let onSelect: (TOCItem) -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Text("OUTLINE")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 10)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                if items.isEmpty {
                    TOCPlaceholder(theme: theme, isLoading: isLoading)
                } else {
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                        Button {
                            onSelect(item)
                        } label: {
                            TOCRow(
                                item: item,
                                isActive: idx == activeLineIndex,
                                previousLevel: idx > 0 ? items[idx - 1].level : nil
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 10)
        }
        .background(panelBackground)
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(theme.editorBackground.opacity(theme.isDark ? 0.3 : 0.58))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(theme.separator.opacity(theme.isDark ? 0.18 : 0.12), lineWidth: 1)
            )
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
    }
}

private struct TOCPlaceholder: View {
    let theme: PreviewTheme
    let isLoading: Bool

    private let widths: [CGFloat] = [0.78, 0.62, 0.7, 0.54]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(widths.enumerated()), id: \.offset) { idx, width in
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.primary.opacity(opacity(for: idx)))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(width: width * 156, height: height(for: idx), alignment: .leading)
                    .padding(.leading, leadingInset(for: idx))
            }

            if isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: 52, height: 8)
                }
                .padding(.top, 6)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func opacity(for index: Int) -> Double {
        isLoading ? 0.08 - (Double(index) * 0.01) : 0.05 - (Double(index) * 0.006)
    }

    private func height(for index: Int) -> CGFloat {
        index == 0 ? 10 : 8
    }

    private func leadingInset(for index: Int) -> CGFloat {
        switch index {
        case 1: return 12
        case 2: return 24
        case 3: return 12
        default: return 0
        }
    }
}

private struct TOCRow: View {
    let item: TOCItem
    let isActive: Bool
    let previousLevel: Int?

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Color.clear
                .frame(width: indentation)

            Text(item.title)
                .font(.system(size: fontSize, weight: fontWeight))
                .foregroundStyle(foregroundStyle)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .truncationMode(.tail)
                .lineSpacing(1.2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 12)
                .padding(.trailing, 10)
                .padding(.vertical, verticalPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(backgroundStyle)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(isActive ? Color.accentColor : levelStripeColor)
                        .frame(width: stripeWidth)
                        .padding(.vertical, 5)
                        .opacity(isActive || item.level >= 3 ? 1 : 0)
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .padding(.top, topSpacing)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.15), value: isActive)
    }

    private var indentation: CGFloat {
        CGFloat((item.level - 1).clamped(to: 0...5)) * 12
    }

    private var topSpacing: CGFloat {
        guard let previousLevel else { return 0 }
        if item.level == 1 {
            return 8
        }
        if item.level <= previousLevel {
            return item.level == 2 ? 6 : 3
        }
        return 2
    }

    private var fontSize: CGFloat {
        switch item.level {
        case 1: return 12.5
        case 2: return 11.5
        default: return 10.5
        }
    }

    private var fontWeight: Font.Weight {
        if isActive { return .semibold }
        switch item.level {
        case 1: return .semibold
        case 2: return .medium
        default: return .regular
        }
    }

    private var verticalPadding: CGFloat {
        switch item.level {
        case 1: return 7
        case 2: return 6
        default: return 5
        }
    }

    private var backgroundStyle: some ShapeStyle {
        if isActive {
            return Color.accentColor.opacity(0.09)
        }
        return Color.clear
    }

    private var foregroundStyle: some ShapeStyle {
        if isActive {
            return Color.primary
        }
        switch item.level {
        case 1:
            return Color.primary.opacity(0.8)
        case 2:
            return Color.primary.opacity(0.62)
        default:
            return Color.secondary.opacity(0.95)
        }
    }

    private var levelStripeColor: Color {
        Color.secondary.opacity(0.14)
    }

    private var stripeWidth: CGFloat {
        isActive ? 3 : 1
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
