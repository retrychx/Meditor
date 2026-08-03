// make_icon_v7.swift — MEditor 图标 v7：老风格重设计「文本行 + 输入光标」。
// 光标不再是一根跨行竖条（读音像 F），而是放在最后一行末尾——
// 正在打字的位置，编辑器/终端图标的经典读法。
//   A: 朱红光标（品牌色）  B: 蓝色光标（向老图标致敬）
// Run: swift tools/make_icon_v7.swift <output_dir>
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

let paper = NSColor(srgbRed: 0.957, green: 0.961, blue: 0.949, alpha: 1)  // 宣纸白
let seal  = NSColor(srgbRed: 0.753, green: 0.224, blue: 0.169, alpha: 1)  // 朱砂
let blue  = NSColor(srgbRed: 0.392, green: 0.537, blue: 0.965, alpha: 1)  // 老图标蓝 #6489F6

func rr(_ r: CGRect, _ rad: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil)
}

func canvas(_ px: Int) -> (NSBitmapImageRep, CGContext) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ctx
    return (rep, ctx.cgContext)
}

/// 质感黑底：墨蓝纵向渐变 + 轻暗角（与 v6 一致）。
func paintBlackGround(_ cg: CGContext, s: CGFloat) {
    let space = CGColorSpaceCreateDeviceRGB()
    let top = NSColor(srgbRed: 0.145, green: 0.180, blue: 0.247, alpha: 1)
    let bot = NSColor(srgbRed: 0.072, green: 0.094, blue: 0.137, alpha: 1)
    let g = CGGradient(colorsSpace: space, colors: [top.cgColor, bot.cgColor] as CFArray, locations: [0, 1])!
    cg.drawLinearGradient(g, start: CGPoint(x: s * 0.3, y: s), end: CGPoint(x: s * 0.7, y: 0), options: [])
    let vignette = CGGradient(colorsSpace: space,
        colors: [NSColor.clear.cgColor, NSColor.black.withAlphaComponent(0.16).cgColor] as CFArray,
        locations: [0.55, 1])!
    cg.drawRadialGradient(vignette, startCenter: CGPoint(x: s/2, y: s/2), startRadius: 0,
        endCenter: CGPoint(x: s/2, y: s/2), endRadius: s * 0.72, options: .drawsAfterEndLocation)
}

func render(_ px: Int, cursor: NSColor, tinted: Bool = false) -> Data {
    let s = CGFloat(px)
    let (rep, cg) = canvas(px)
    if tinted {
        cg.clear(CGRect(x: 0, y: 0, width: s, height: s))
    } else {
        paintBlackGround(cg, s: s)
    }

    let stroke = s * 0.082
    let radius = stroke / 2
    let lineGap = stroke * 0.72
    // 三行文本，左对齐：上行最长、末行最短（真实段落节奏）
    // 注意 Quartz 坐标 y 向上：视觉上的「上方」是大 y
    let textX = s * 0.265
    let widths: [CGFloat] = [s * 0.42, s * 0.33, s * 0.20]
    let blockH = stroke * 3 + lineGap * 2
    let yTop = (s + blockH) / 2 - stroke / 2   // 首行（最上方）中心 y

    cg.setFillColor((tinted ? NSColor(white: 0.62, alpha: 1) : paper).cgColor)
    for (i, w) in widths.enumerated() {
        let cy = yTop - CGFloat(i) * (stroke + lineGap)
        cg.addPath(rr(CGRect(x: textX, y: cy - stroke/2, width: w, height: stroke), radius))
        cg.fillPath()
    }

    if !tinted {
        // 输入光标：紧跟末行（最下方、最短的那行）末尾，高度略大于字行
        let lastY = yTop - 2 * (stroke + lineGap)
        let curW = stroke * 0.52
        let curH = stroke * 1.28
        let curX = textX + widths[2] + stroke * 0.42
        cg.setFillColor(cursor.cgColor)
        cg.addPath(rr(CGRect(x: curX, y: lastY - curH/2, width: curW, height: curH), curW/2))
        cg.fillPath()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

try! render(1024, cursor: seal).write(to: URL(fileURLWithPath: "\(outDir)/v7-red-1024.png"))
try! render(1024, cursor: blue).write(to: URL(fileURLWithPath: "\(outDir)/v7-blue-1024.png"))
try! render(1024, cursor: seal, tinted: true).write(to: URL(fileURLWithPath: "\(outDir)/v7-tinted-1024.png"))

/// macOS 磁贴式：透明外边距 + 圆角磁贴（Big Sur 风格，边距 ~10%）。
func renderMacTile(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ctx
    let cg = ctx.cgContext

    let margin = s * 0.10
    let inner = s - margin * 2
    let tile = CGRect(x: margin, y: margin, width: inner, height: inner)
    cg.saveGState()
    cg.addPath(rr(tile, inner * 0.2237)); cg.clip()
    cg.translateBy(x: margin, y: margin)
    cg.scaleBy(x: inner / s, y: inner / s)
    paintBlackGround(cg, s: s)

    let stroke = s * 0.082
    let radius = stroke / 2
    let lineGap = stroke * 0.72
    let textX = s * 0.265
    let widths: [CGFloat] = [s * 0.42, s * 0.33, s * 0.20]
    let blockH = stroke * 3 + lineGap * 2
    let yTop = (s + blockH) / 2 - stroke / 2
    cg.setFillColor(paper.cgColor)
    for (i, w) in widths.enumerated() {
        let cy = yTop - CGFloat(i) * (stroke + lineGap)
        cg.addPath(rr(CGRect(x: textX, y: cy - stroke/2, width: w, height: stroke), radius))
        cg.fillPath()
    }
    let lastY = yTop - 2 * (stroke + lineGap)
    let curW = stroke * 0.52
    let curH = stroke * 1.28
    cg.setFillColor(seal.cgColor)
    cg.addPath(rr(CGRect(x: textX + widths[2] + stroke * 0.42, y: lastY - curH/2, width: curW, height: curH), curW/2))
    cg.fillPath()
    cg.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512, 1024] {
    try! renderMacTile(size).write(to: URL(fileURLWithPath: "\(outDir)/v7-mac-\(size).png"))
}
print("done → \(outDir)")
