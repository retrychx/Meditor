import SwiftUI

/// A left-side outline showing document headings for quick navigation.
struct TOCOutlineView: View {
    let items: [TOCItem]
    let activeLineIndex: Int
    let onSelect: (TOCItem) -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 1) {
                Text("OUTLINE")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 10)
                    .padding(.top, 10)
                    .padding(.bottom, 4)

                ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                    Button {
                        onSelect(item)
                    } label: {
                        TOCRow(item: item, isActive: idx == activeLineIndex)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 8)
        }
    }
}

private struct TOCRow: View {
    let item: TOCItem
    let isActive: Bool

    var body: some View {
        HStack(spacing: 4) {
            // Active indicator bar
            RoundedRectangle(cornerRadius: 1)
                .fill(isActive ? Color.accentColor : .clear)
                .frame(width: 2)

            Text(item.title)
                .font(.system(size: fontSize, weight: fontWeight))
                .foregroundStyle(isActive ? .primary : .secondary)
                .lineLimit(2)
                .truncationMode(.tail)
                .padding(.leading, indentation)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isActive ? Color.accentColor.opacity(0.08) : .clear)
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.15), value: isActive)
    }

    private var indentation: CGFloat {
        CGFloat((item.level - 1).clamped(to: 0...5)) * 10
    }

    private var fontSize: CGFloat {
        switch item.level {
        case 1: return 12
        case 2: return 11.5
        default: return 11
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
