import SwiftUI

/// A left-side outline showing document headings for quick navigation.
struct TOCOutlineView: View {
    let items: [TOCItem]
    let activeLineIndex: Int
    let onSelect: (TOCItem) -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 2) {
                Text("OUTLINE")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 6)

                ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                    Button {
                        onSelect(item)
                    } label: {
                        TOCRow(item: item, isActive: idx == activeLineIndex)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 10)
        }
    }
}

private struct TOCRow: View {
    let item: TOCItem
    let isActive: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            // Active indicator bar
            RoundedRectangle(cornerRadius: 1)
                .fill(isActive ? Color.accentColor : .clear)
                .frame(width: 2)

            Text(item.title)
                .font(.system(size: fontSize, weight: fontWeight))
                .foregroundStyle(isActive ? .primary : .secondary)
                .lineLimit(3)
                .truncationMode(.tail)
                .lineSpacing(1.5)
                .padding(.leading, indentation)
        }
        .padding(.vertical, 5)
        .padding(.leading, 8)
        .padding(.trailing, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isActive ? Color.accentColor.opacity(0.08) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.15), value: isActive)
    }

    private var indentation: CGFloat {
        CGFloat((item.level - 1).clamped(to: 0...5)) * 8
    }

    private var fontSize: CGFloat {
        switch item.level {
        case 1: return 11.5
        case 2: return 11
        default: return 10.5
        }
    }

    private var fontWeight: Font.Weight {
        if isActive { return .semibold }
        return item.level <= 2 ? .medium : .regular
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
