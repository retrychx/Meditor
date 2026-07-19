import Foundation
import Observation

/// 演讲模式入口：负责分页并管理全屏放映窗口的生命周期。
@MainActor
@Observable
final class PresentationManager {
    /// 是否正在放映（供 UI 禁用/状态展示）。
    private(set) var isPresenting = false

    @ObservationIgnored
    private var windowController: PresentationWindowController?

    /// 把 Markdown 文档按 `---` 分页后全屏放映。单页文档也可放映。
    func start(markdown: String, sourceURL: URL?, theme: PreviewTheme) {
        guard !isPresenting else { return }
        let slides = SlideSplitter.split(markdown)
        guard !slides.isEmpty else { return }

        let controller = PresentationWindowController()
        controller.onDidClose = { [weak self] in
            guard let self else { return }
            self.windowController = nil
            self.isPresenting = false
        }
        // 资源缺失等原因导致未真正开窗时，不进入放映状态
        guard controller.present(slides: slides, sourceURL: sourceURL, theme: theme) else { return }
        windowController = controller
        isPresenting = true
    }

    func stop() {
        windowController?.closePresentation()
    }

    /// 放映中实时切换主题（主窗口预览主题变化时由 AppState 转发）。
    func applyTheme(_ theme: PreviewTheme) {
        windowController?.applyTheme(theme)
    }
}
