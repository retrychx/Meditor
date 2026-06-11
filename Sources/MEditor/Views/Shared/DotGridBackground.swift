import SwiftUI

/// A subtle dot-grid background that gives empty areas a "paper" feel
/// without being distracting. Dots are barely visible — just enough to
/// break the void.
struct DotGridBackground: View {
    var spacing: CGFloat = 20
    var dotSize: CGFloat = 1.3
    var opacity: Double = 0.22

    var body: some View {
        Canvas { context, size in
            let cols = Int(size.width / spacing) + 1
            let rows = Int(size.height / spacing) + 1
            for row in 0..<rows {
                for col in 0..<cols {
                    let point = CGPoint(x: CGFloat(col) * spacing, y: CGFloat(row) * spacing)
                    let rect = CGRect(
                        x: point.x - dotSize / 2,
                        y: point.y - dotSize / 2,
                        width: dotSize,
                        height: dotSize
                    )
                    context.fill(Circle().path(in: rect), with: .color(.primary.opacity(opacity)))
                }
            }
        }
    }
}
