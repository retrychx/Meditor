// make_icon_ios.swift — MEditor iOS app icon: full-bleed ink background + blockquote mark.
// iOS 图标不允许透明通道/留白边：整幅铺满，圆角由系统裁切。
// Run: swift tools/make_icon_ios.swift <output_png_path>
import AppKit

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "appicon-1024.png"

let ink    = NSColor(srgbRed: 0.09, green: 0.09, blue: 0.11, alpha: 1)
let accent = NSColor(srgbRed: 0.42, green: 0.55, blue: 1.00, alpha: 1)
let line   = NSColor(white: 0.97, alpha: 1)

func rr(_ r: CGRect, _ rad: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil)
}

func drawMark(_ cg: CGContext, _ rect: CGRect) {
    let w  = rect.width * 0.52
    let bw = rect.width * 0.078
    let gap = rect.width * 0.073
    let bh = rect.width * 0.375
    let t  = rect.width * 0.075
    let x0 = rect.midX - w / 2

    // Blockquote bar (accent), spanning the full mark height.
    cg.setFillColor(accent.cgColor)
    cg.addPath(rr(CGRect(x: x0, y: rect.midY - bh/2, width: bw, height: bh), bw/2)); cg.fillPath()

    // Two quoted text lines (white): top full-width, bottom shorter.
    let lx = x0 + bw + gap
    let lw = w - bw - gap
    cg.setFillColor(line.cgColor)
    cg.addPath(rr(CGRect(x: lx, y: rect.midY + bh/2 - t, width: lw, height: t), t/2)); cg.fillPath()
    cg.addPath(rr(CGRect(x: lx, y: rect.midY - bh/2, width: lw * 0.66, height: t), t/2)); cg.fillPath()
}

let px = 1024
let size = CGFloat(px)
// RGBA 渲染（整幅不透明），写盘后用 sips 去 alpha（App Store 要求）。
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let ctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = ctx
let cg = ctx.cgContext
let rect = CGRect(x: 0, y: 0, width: size, height: size)

cg.setFillColor(ink.cgColor); cg.fill(rect)
// very subtle top highlight for depth
let space = CGColorSpaceCreateDeviceRGB()
let g = CGGradient(colorsSpace: space,
    colors: [NSColor.white.withAlphaComponent(0.05).cgColor, NSColor.clear.cgColor] as CFArray,
    locations: [0, 1])!
cg.drawLinearGradient(g, start: CGPoint(x: rect.midX, y: rect.maxY),
    end: CGPoint(x: rect.midX, y: rect.midY), options: [])

drawMark(cg, rect)

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
