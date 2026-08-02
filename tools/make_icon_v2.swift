// make_icon_v2.swift — MEditor iOS 图标候选 v2：「光标 + 文本行」。
// 竖条 = 光标（朱砂），横条 = 文字行（墨/纸）——编辑器最直接的图形语言。
// 输出多个变体供对比：墨底/纸底 × 是否微渐变。
// Run: swift tools/make_icon_v2.swift <output_dir>
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

let paper  = NSColor(srgbRed: 0.957, green: 0.961, blue: 0.949, alpha: 1)  // 宣纸白 #F4F5F2
let ink    = NSColor(srgbRed: 0.106, green: 0.141, blue: 0.204, alpha: 1)  // 松烟墨 #1B2434
let inkHi  = NSColor(srgbRed: 0.165, green: 0.204, blue: 0.282, alpha: 1)  // 墨亮部 #2A3448
let seal   = NSColor(srgbRed: 0.753, green: 0.224, blue: 0.169, alpha: 1)  // 朱砂 #C0392B
let sealHi = NSColor(srgbRed: 0.835, green: 0.310, blue: 0.235, alpha: 1)  // 朱砂亮部

func rr(_ r: CGRect, _ rad: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil)
}

/// 图形本体：在给定画布中心绘制「光标 + 两行文本」。
/// 比例按 1024 画布精调：笔画宽度统一，间距按笔画宽度的倍数取整。
func drawMark(_ cg: CGContext, size: CGFloat, cursor: NSColor, lines: NSColor) {
    let s = size
    let stroke = s * 0.085               // 统一笔画宽
    let radius = stroke / 2
    // 整体图形容量：宽 0.46s，高 0.40s，视觉中心略上移（图标惯例）
    let markW = s * 0.46
    let markH = s * 0.40
    let ox = (s - markW) / 2
    let oy = (s - markH) / 2 + s * 0.012

    // 光标（竖条）：与横条同宽笔画，高度 = 两个文本行的总高
    let cursorRect = CGRect(x: ox, y: oy, width: stroke, height: markH)
    // 横条间距：上行顶 = 图形顶，下行底 = 图形底
    let gapX = stroke * 0.55             // 光标与横条间距
    let lineX = ox + stroke + gapX
    let lineW1 = markW - stroke - gapX          // 上行：长
    let lineW2 = lineW1 * 0.62                  // 下行：短（节奏）
    let midGap = markH - stroke * 2             // 两行之间的空白
    let line1 = CGRect(x: lineX, y: oy, width: lineW1, height: stroke)
    let line2 = CGRect(x: lineX, y: oy + stroke + midGap, width: lineW2, height: stroke)

    // 朱砂光标带一线顶部亮部（细微体积感，不是投影）
    cg.setFillColor(cursor.cgColor)
    cg.addPath(rr(cursorRect, radius)); cg.fillPath()
    cg.saveGState()
    cg.addPath(rr(cursorRect, radius)); cg.clip()
    let space = CGColorSpaceCreateDeviceRGB()
    let g = CGGradient(colorsSpace: space,
        colors: [sealHi.withAlphaComponent(0.6).cgColor, NSColor.clear.cgColor] as CFArray,
        locations: [0, 0.5])!
    cg.drawLinearGradient(g, start: CGPoint(x: cursorRect.midX, y: cursorRect.maxY),
        end: CGPoint(x: cursorRect.midX, y: cursorRect.midY), options: [])
    cg.restoreGState()

    cg.setFillColor(lines.cgColor)
    cg.addPath(rr(line1, radius)); cg.fillPath()
    cg.addPath(rr(line2, radius)); cg.fillPath()
}

func render(_ px: Int, bg: NSColor, bgGradientTo: NSColor?, cursor: NSColor, lines: NSColor) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ctx
    let cg = ctx.cgContext
    let rect = CGRect(x: 0, y: 0, width: s, height: s)

    cg.setFillColor(bg.cgColor); cg.fill(rect)
    if let bgTo = bgGradientTo {
        let space = CGColorSpaceCreateDeviceRGB()
        let g = CGGradient(colorsSpace: space,
            colors: [bgTo.cgColor, bg.cgColor] as CFArray, locations: [0, 1])!
        cg.drawLinearGradient(g, start: CGPoint(x: s * 0.2, y: s),
            end: CGPoint(x: s * 0.8, y: 0), options: [])
    }

    drawMark(cg, size: s, cursor: cursor, lines: lines)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

// A：墨底（微渐变）+ 朱砂光标 + 纸白文本行 —— 与 macOS 图标同族，品牌色
try! render(1024, bg: ink, bgGradientTo: inkHi, cursor: seal, lines: paper)
    .write(to: URL(fileURLWithPath: "\(outDir)/v2-ink-1024.png"))
// B：纸底 + 朱砂光标 + 墨文本行 —— 与 iOS 纸墨主题一致
try! render(1024, bg: paper, bgGradientTo: nil, cursor: seal, lines: ink)
    .write(to: URL(fileURLWithPath: "\(outDir)/v2-paper-1024.png"))
print("done → \(outDir)")
