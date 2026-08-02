// make_seal_icon.swift — MEditor「墨字印章」图标，纸底/墨底两款，iOS 满幅 + macOS 磁贴式。
// 印章与 app 内 SealStamp 同源：朱砂方印 + 白色楷体「墨」+ 微斜 + 软影。
// Run: swift tools/make_seal_icon.swift <output_dir>
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

// 品牌色（与 PaperTheme 一致）
let paper  = NSColor(srgbRed: 0.957, green: 0.961, blue: 0.949, alpha: 1)   // 宣纸白 #F4F5F2
let ink    = NSColor(srgbRed: 0.106, green: 0.141, blue: 0.204, alpha: 1)   // 松烟墨 #1B2434
let seal   = NSColor(srgbRed: 0.753, green: 0.224, blue: 0.169, alpha: 1)   // 朱砂 #C0392B
let sealHi = NSColor(srgbRed: 0.835, green: 0.310, blue: 0.235, alpha: 1)   // 朱砂亮部

func rr(_ r: CGRect, _ rad: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil)
}

/// 楷体「墨」：印章的刀刻感来自楷体而非黑体；逐级回退保证字体可用。
func sealFont(_ size: CGFloat) -> NSFont {
    for name in ["Kaiti SC Bold", "Kaiti SC", "Songti SC Bold", "STKaiti", "KaiTi"] {
        if let f = NSFont(name: name, size: size) { return f }
    }
    return NSFont.boldSystemFont(ofSize: size)
}

/// 在 rect 中心绘制印章（微斜 3°）。
func drawSeal(_ cg: CGContext, in rect: CGRect, side: CGFloat) {
    let sealRect = CGRect(x: rect.midX - side/2, y: rect.midY - side/2, width: side, height: side)
    let radius = side * 0.19

    cg.saveGState()
    // 绕印章中心转 3°
    cg.translateBy(x: sealRect.midX, y: sealRect.midY)
    cg.rotate(by: -3 * .pi / 180)
    cg.translateBy(x: -sealRect.midX, y: -sealRect.midY)

    // 软影（透过印章形状投影）
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -side * 0.018), blur: side * 0.05,
                 color: NSColor.black.withAlphaComponent(0.22).cgColor)
    cg.setFillColor(seal.cgColor)
    cg.addPath(rr(sealRect, radius)); cg.fillPath()
    cg.restoreGState()

    // 章体：底部朱砂 + 顶部一线亮部（印泥的微微起伏）
    cg.saveGState()
    cg.addPath(rr(sealRect, radius)); cg.clip()
    cg.setFillColor(seal.cgColor); cg.fill(sealRect)
    let space = CGColorSpaceCreateDeviceRGB()
    let g = CGGradient(colorsSpace: space,
        colors: [sealHi.withAlphaComponent(0.55).cgColor, NSColor.clear.cgColor] as CFArray,
        locations: [0, 0.45])!
    cg.drawLinearGradient(g, start: CGPoint(x: sealRect.midX, y: sealRect.maxY),
        end: CGPoint(x: sealRect.midX, y: sealRect.midY), options: [])
    cg.restoreGState()

    // 白字「墨」：按字形实际包围盒居中（视觉居中，非基线居中）
    let font = sealFont(side * 0.60)
    let str = NSAttributedString(string: "墨", attributes: [
        .font: font,
        .foregroundColor: NSColor(srgbRed: 1.0, green: 0.985, blue: 0.965, alpha: 1),
    ])
    let bounds = str.boundingRect(with: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
    let origin = CGPoint(x: sealRect.midX - bounds.width / 2 - bounds.origin.x,
                         y: sealRect.midY - bounds.height / 2 - bounds.origin.y)
    str.draw(at: origin)

    cg.restoreGState()
}

/// iOS 满幅（不透明，圆角系统裁切）。
func renderFullBleed(_ px: Int, bg: NSColor) -> Data {
    let size = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ctx
    let cg = ctx.cgContext
    let rect = CGRect(x: 0, y: 0, width: size, height: size)

    cg.setFillColor(bg.cgColor); cg.fill(rect)
    // 满幅不做顶部受光——大画布上渐变会露出亮带；深度由印章自身的亮部承担。

    drawSeal(cg, in: rect, side: size * 0.46)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

/// macOS 磁贴式（透明外边距 + 圆角磁贴）。
func renderTile(_ px: Int, bg: NSColor) -> Data {
    let size = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ctx
    let cg = ctx.cgContext

    let margin = size * 0.10
    let inner = size - margin * 2
    let rect = CGRect(x: margin, y: margin, width: inner, height: inner)

    cg.saveGState()
    cg.addPath(rr(rect, inner * 0.2237)); cg.clip()
    cg.setFillColor(bg.cgColor); cg.fill(rect)
    let space = CGColorSpaceCreateDeviceRGB()
    let g = CGGradient(colorsSpace: space,
        colors: [NSColor.white.withAlphaComponent(0.05).cgColor, NSColor.clear.cgColor] as CFArray,
        locations: [0, 1])!
    cg.drawLinearGradient(g, start: CGPoint(x: rect.midX, y: rect.maxY),
        end: CGPoint(x: rect.midX, y: rect.midY), options: [])
    cg.restoreGState()

    drawSeal(cg, in: rect, side: inner * 0.52)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

// 两款 × 两种形态
try! renderFullBleed(1024, bg: paper).write(to: URL(fileURLWithPath: "\(outDir)/seal-paper-ios-1024.png"))
try! renderFullBleed(1024, bg: ink).write(to: URL(fileURLWithPath: "\(outDir)/seal-ink-ios-1024.png"))
for s in [128, 256, 512, 1024] {
    try! renderTile(s, bg: paper).write(to: URL(fileURLWithPath: "\(outDir)/seal-paper-mac-\(s).png"))
    try! renderTile(s, bg: ink).write(to: URL(fileURLWithPath: "\(outDir)/seal-ink-mac-\(s).png"))
}
print("done → \(outDir)")
