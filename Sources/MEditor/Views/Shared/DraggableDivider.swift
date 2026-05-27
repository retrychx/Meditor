import SwiftUI

/// A draggable divider for resizable panels.
struct DraggableDivider: View {
    @Binding var width: CGFloat
    let minValue: CGFloat
    let maxValue: CGFloat

    var body: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.2))
            .frame(width: 1)
            .contentShape(Rectangle().inset(by: -3))
            .gesture(
                DragGesture()
                    .onChanged { value in
                        width = min(max(width + value.translation.width, minValue), maxValue)
                    }
            )
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() }
                else { NSCursor.pop() }
            }
    }
}
