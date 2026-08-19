import Foundation
import CoreGraphics

/// PDF 导出选项：纸张、页边距、页眉页脚、封面页。
/// 纯值类型，持久化走 AppSettings 的 rawValue 键（见 AppSettings.pdfExportOptions）。
struct PDFExportOptions: Equatable, Sendable {

    enum PaperSize: String, CaseIterable, Sendable {
        case a4
        case letter

        /// 页面尺寸（points，72dpi，纵向）。
        var pointsSize: CGSize {
            switch self {
            case .a4:     return CGSize(width: 595.28, height: 841.89)
            case .letter: return CGSize(width: 612, height: 792)
            }
        }

        /// CSS @page size 关键字。
        var cssKeyword: String {
            switch self {
            case .a4:     return "A4"
            case .letter: return "letter"
            }
        }

        var labelKey: String {
            switch self {
            case .a4:     return "pdf.paper.a4"
            case .letter: return "pdf.paper.letter"
            }
        }
    }

    enum MarginPreset: String, CaseIterable, Sendable {
        case narrow   // 36pt  ≈ 12.7mm
        case normal   // 54pt  ≈ 19mm
        case wide     // 72pt  = 25.4mm

        var points: CGFloat {
            switch self {
            case .narrow: return 36
            case .normal: return 54
            case .wide:   return 72
            }
        }

        var labelKey: String {
            switch self {
            case .narrow: return "pdf.margins.narrow"
            case .normal: return "pdf.margins.normal"
            case .wide:   return "pdf.margins.wide"
            }
        }
    }

    var paperSize: PaperSize = .a4
    var margins: MarginPreset = .normal
    var showHeader: Bool = false   // 页眉：文档标题
    var showFooter: Bool = false   // 页脚：页码
    var coverPage: Bool = false    // 封面页：标题 + 日期

    static let `default` = PDFExportOptions()

    /// 无需任何后处理的默认配置（A4 + 标准边距 + 无页眉页脚封面）。
    /// 为 true 时导出直接写 WebKit 原始 PDF，跳过 PDFDocumentDecorator 重绘——
    /// 重绘走 drawPDFPage，不保留链接 annotation（导出 PDF 链接全灭）。
    var isDefault: Bool { self == .default }

    /// 注入打印用 HTML 的样式：让 WebKit 按目标纸张分页、页边距归零——
    /// 真正的边距由 PDFDocumentDecorator 在后处理阶段统一施加（缩放进内容区），
    /// 这样无论 WebKit 是否认 @page margin，最终边距都确定。
    /// 仅非默认选项（会走装饰）时注入；默认选项不注入，保留 WebKit 自带分页与边距。
    func printCSS() -> String {
        "@page { size: \(paperSize.cssKeyword); margin: 0; }"
    }

    /// 页面矩形（points）。
    var pageRect: CGRect { CGRect(origin: .zero, size: paperSize.pointsSize) }

    /// 正文内容区 = 页面减去四边边距。
    var contentRect: CGRect { pageRect.insetBy(dx: margins.points, dy: margins.points) }
}
