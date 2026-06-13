import SwiftUI

/// Subtle dot-grid that gives empty areas a refined "paper" texture.
struct DotGridBackground: View {
    var spacing: CGFloat = 20
    var dotSize: CGFloat = 1.4
    var opacity: Double  = 0.45

    var body: some View {
        Canvas { context, size in
            let inset: CGFloat = 16
            let cols = Int((size.width  - inset * 2) / spacing)
            let rows = Int((size.height - inset * 2) / spacing)
            for row in 0...rows {
                for col in 0...cols {
                    let pt = CGPoint(
                        x: inset + CGFloat(col) * spacing,
                        y: inset + CGFloat(row) * spacing
                    )
                    let rect = CGRect(
                        x: pt.x - dotSize / 2,
                        y: pt.y - dotSize / 2,
                        width: dotSize,
                        height: dotSize
                    )
                    context.fill(
                        Circle().path(in: rect),
                        with: .color(.primary.opacity(opacity))
                    )
                }
            }
        }
    }
}
