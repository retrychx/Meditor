import AppKit
import Foundation

// MARK: - AI 聊天图片处理

/// 聊天图片输入的统一处理：任意来源（粘贴板 / 拖拽文件）→ 内存 JPEG 附件。
/// 约束：单条消息最多 4 张；每张长边 ≤1568px（等比缩小）、体积 ≤1MB（质量自适应）。
enum AIImageProcessor {

    /// 长边上限（像素）：与主流多模态模型的推荐输入尺寸对齐，再大收益递减
    static let maxLongEdge: CGFloat = 1568
    /// 单张处理后体积上限（字节）
    static let maxBytes = 1_000_000
    /// 单条消息附件上限
    static let maxAttachmentsPerMessage = 4

    /// JPEG 质量自适应阶梯：从高到低尝试，首个 ≤1MB 的档位胜出。
    /// 1568px 的 JPEG 在 q0.3 档通常已远小于 1MB，触底仍超限（极端噪声图）则拒绝该图。
    private static let qualityLadder: [Double] = [0.85, 0.7, 0.55, 0.4, 0.3, 0.2]

    // MARK: 处理入口

    /// NSImage → 聊天附件：统一转 JPEG，长边超限时先等比缩小，再质量自适应压到 1MB 内。
    /// 返回 nil = 无法处理（非法位图 / 压不到 1MB 内），调用方应跳过该图。
    static func makeAttachment(from image: NSImage) -> AIImageAttachment? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }
        return makeAttachment(from: cgImage)
    }

    /// CGImage 版本（测试与内部复用）。
    static func makeAttachment(from cgImage: CGImage) -> AIImageAttachment? {
        // 质量阶梯触底仍超限的极端情况（噪声大图），降一半分辨率再试一轮；
        // 仍压不进 1MB 则拒绝该图（上限是硬约束）。
        for extraScale in [1.0, 0.5] {
            guard let rep = resizedRep(cgImage, extraScale: extraScale) else { continue }
            for quality in qualityLadder {
                guard let data = rep.representation(
                    using: .jpeg, properties: [.compressionFactor: NSNumber(value: quality)]
                ) else { continue }
                if data.count <= maxBytes {
                    return AIImageAttachment(
                        mimeType: "image/jpeg", data: data,
                        width: rep.pixelsWide, height: rep.pixelsHigh
                    )
                }
            }
        }
        return nil
    }

    /// 图片文件 → 聊天附件（拖拽进入用）。非图片 / 解码失败返回 nil。
    static func makeAttachment(fromFileURL url: URL) -> AIImageAttachment? {
        guard let image = NSImage(contentsOf: url) else { return nil }
        return makeAttachment(from: image)
    }

    // MARK: 粘贴板提取

    /// 从粘贴板提取聊天图片附件（与编辑器粘贴落盘不同，这里只走内存）：
    /// 1) 文件 URL 优先（Finder ⌘C / 从浏览器拖出的图片文件）
    /// 2) 粘贴板直接携带的位图数据兜底（截图等无文件来源的场景，PNG/TIFF）
    static func attachments(from pasteboard: NSPasteboard) -> [AIImageAttachment] {
        let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        let fromFiles = urls.compactMap { makeAttachment(fromFileURL: $0) }
        if !fromFiles.isEmpty { return fromFiles }

        // 截图：TIFF/PNG flavor，先包成 NSImage 再走统一 JPEG 管线
        if let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff),
           let image = NSImage(data: data),
           let attachment = makeAttachment(from: image) {
            return [attachment]
        }
        return []
    }

    // MARK: 附件上限

    /// 追加上限控制：最多保留 limit 张，超出的丢弃。
    /// 返回 (追加后的数组, 被拒绝的数量)，被拒绝数供 UI 提示（第 5 张起拒收）。
    static func appending(
        _ new: [AIImageAttachment],
        to existing: [AIImageAttachment],
        limit: Int = maxAttachmentsPerMessage
    ) -> (merged: [AIImageAttachment], rejected: Int) {
        let room = max(0, limit - existing.count)
        let accepted = new.prefix(room)
        return (existing + accepted, new.count - accepted.count)
    }

    // MARK: - 内部

    /// 长边超限则等比缩小到 maxLongEdge 内，返回位图 rep；未超限且 extraScale=1 直接包装。
    /// extraScale < 1 用于质量阶梯触底后的二次降分辨率兜底。
    private static func resizedRep(_ cgImage: CGImage, extraScale: CGFloat) -> NSBitmapImageRep? {
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let longEdge = max(width, height)
        var scale = extraScale
        if longEdge > maxLongEdge { scale *= maxLongEdge / longEdge }
        guard scale < 0.999 else {
            return NSBitmapImageRep(cgImage: cgImage)
        }
        let newWidth = max(1, Int((width * scale).rounded()))
        let newHeight = max(1, Int((height * scale).rounded()))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: newWidth, pixelsHigh: newHeight,
            bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current = context
        context?.imageInterpolation = .high
        // 焦点外绘图：flipped 坐标系下按 (0,0,w,h) 铺满即可
        NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
            .draw(in: NSRect(x: 0, y: 0, width: newWidth, height: newHeight))
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }
}
