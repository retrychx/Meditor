import Foundation
import CoreGraphics
import PDFKit
import AppKit

/// PDF 导出后处理：把 WebKit createPDF 产出的原始 PDF 重排到目标纸张上——
/// 源页等比缩放进「纸张 - 页边距」的内容区，按需加封面页、页眉（文档标题）、
/// 页脚（页码）。输入/输出都是 Data，纯函数，可单测。
enum PDFDocumentDecorator {

    /// 装饰一份 PDF。解析失败或写不出新 PDF 时返回 nil（调用方回退原始数据）。
    /// - Parameters:
    ///   - data: 原始 PDF 数据。
    ///   - options: 纸张/边距/页眉页脚/封面配置。
    ///   - title: 文档标题（页眉与封面用）。
    ///   - date: 封面上的日期。
    static func decorate(data: Data,
                         options: PDFExportOptions,
                         title: String,
                         date: Date = Date()) -> Data? {
        guard let document = PDFDocument(data: data), document.pageCount > 0 else { return nil }

        let pageRect = options.pageRect
        let contentRect = options.contentRect
        let out = NSMutableData()
        // 注意：页尺寸必须在创建 context 时给定——beginPDFPage 字典里的
        // kCGPDFContextMediaBox 在 context 以 nil mediaBox 创建时会被忽略
        // （实测 macOS：输出页落回 drawPDFPage 源页尺寸）。
        var mediaBox = pageRect
        guard let consumer = CGDataConsumer(data: out as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }

        if options.coverPage {
            ctx.beginPDFPage(nil)
            drawCover(in: ctx, pageRect: pageRect, contentRect: contentRect, title: title, date: date)
            ctx.endPDFPage()
        }

        let total = document.pageCount
        for index in 0..<total {
            guard let page = document.page(at: index), let cgPage = page.pageRef else { continue }
            ctx.beginPDFPage(nil)

            // 源页等比缩放进内容区（保持纵横比，居中）
            let src = page.bounds(for: .mediaBox)
            let scale = min(contentRect.width / max(src.width, 1),
                            contentRect.height / max(src.height, 1))
            ctx.saveGState()
            ctx.translateBy(x: contentRect.midX - src.width * scale / 2,
                            y: contentRect.midY - src.height * scale / 2)
            ctx.scaleBy(x: scale, y: scale)
            ctx.drawPDFPage(cgPage)
            ctx.restoreGState()

            // 页眉/页脚画在边距留白里，页码只数正文页（封面不占页码）
            if options.showHeader {
                drawHeader(in: ctx, pageRect: pageRect, margins: options.margins.points, title: title)
            }
            if options.showFooter {
                drawFooter(in: ctx, pageRect: pageRect, margins: options.margins.points,
                           page: index + 1, total: total)
            }
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return out as Data
    }

    // MARK: - 绘制（PDF 上下文原点在左下，统一翻转为左上坐标后画文字）

    private static func withFlippedTextContext(_ ctx: CGContext,
                                               pageHeight: CGFloat,
                                               draw: () -> Void) {
        ctx.saveGState()
        ctx.translateBy(x: 0, y: pageHeight)
        ctx.scaleBy(x: 1, y: -1)
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        draw()
        NSGraphicsContext.current = previous
        ctx.restoreGState()
    }

    private static func centeredParagraph() -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.alignment = .center
        return p
    }

    private static func drawCover(in ctx: CGContext,
                                  pageRect: CGRect,
                                  contentRect: CGRect,
                                  title: String,
                                  date: Date) {
        withFlippedTextContext(ctx, pageHeight: pageRect.height) {
            let titleFont = NSFont.systemFont(ofSize: 30, weight: .bold)
            let dateFont = NSFont.systemFont(ofSize: 13)
            let dateText = DateFormatter.localizedString(from: date, dateStyle: .long, timeStyle: .none)

            let titleRect = CGRect(x: contentRect.minX,
                                   y: pageRect.height * 0.36,
                                   width: contentRect.width,
                                   height: 60)
            (title as NSString).draw(with: titleRect,
                                     options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                                     attributes: [.font: titleFont,
                                                  .foregroundColor: NSColor.labelColor,
                                                  .paragraphStyle: centeredParagraph()])
            let dateRect = CGRect(x: contentRect.minX,
                                  y: titleRect.maxY + 14,
                                  width: contentRect.width,
                                  height: 24)
            (dateText as NSString).draw(with: dateRect,
                                        options: [.usesLineFragmentOrigin],
                                        attributes: [.font: dateFont,
                                                     .foregroundColor: NSColor.secondaryLabelColor,
                                                     .paragraphStyle: centeredParagraph()])
        }
    }

    private static func drawHeader(in ctx: CGContext,
                                   pageRect: CGRect,
                                   margins: CGFloat,
                                   title: String) {
        guard !title.isEmpty else { return }
        withFlippedTextContext(ctx, pageHeight: pageRect.height) {
            let rect = CGRect(x: margins, y: margins * 0.3,
                              width: pageRect.width - margins * 2, height: margins * 0.5)
            (title as NSString).draw(with: rect,
                                     options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                                     attributes: [.font: NSFont.systemFont(ofSize: 9),
                                                  .foregroundColor: NSColor.secondaryLabelColor,
                                                  .paragraphStyle: centeredParagraph()])
        }
    }

    private static func drawFooter(in ctx: CGContext,
                                   pageRect: CGRect,
                                   margins: CGFloat,
                                   page: Int,
                                   total: Int) {
        withFlippedTextContext(ctx, pageHeight: pageRect.height) {
            let text = "\(page) / \(total)"
            let rect = CGRect(x: margins,
                              y: pageRect.height - margins * 0.8,
                              width: pageRect.width - margins * 2,
                              height: margins * 0.5)
            (text as NSString).draw(with: rect,
                                    options: [.usesLineFragmentOrigin],
                                    attributes: [.font: NSFont.systemFont(ofSize: 9),
                                                 .foregroundColor: NSColor.secondaryLabelColor,
                                                 .paragraphStyle: centeredParagraph()])
        }
    }
}
