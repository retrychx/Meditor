import SwiftUI

/// Mermaid 图表块：走共享渲染引擎（MermaidRenderer）出 PNG 图片，
/// 占位 → 图片淡入；不再每块各起一个 WKWebView（旧方案每张图都要解析一遍 3MB 的 JS）。
struct MermaidBlockView: View {
    let code: String

    @Environment(\.displayScale) private var displayScale
    @State private var phase: Phase = .loading

    private enum Phase {
        case loading
        case rendered(UIImage)
        case failed(String)
    }

    var body: some View {
        Group {
            switch phase {
            case .loading:
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("渲染图表中…")
                        .font(.system(size: 12))
                        .foregroundStyle(PaperTheme.inkSecondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 120)

            case .rendered(let image):
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)

            case .failed(let message):
                Text(message)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(PaperTheme.accent)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
        }
        .background(PaperTheme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(PaperTheme.hairline, lineWidth: 0.5)
        }
        .task(id: code) {
            do {
                let rendered = try await MermaidRenderer.shared.render(code: code, scale: displayScale)
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.2)) { phase = .rendered(rendered.image) }
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failed(error.localizedDescription)
            }
        }
    }
}
