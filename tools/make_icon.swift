// make_icon.swift — MEditor app icon: blockquote mark (accent bar + 2 lines) on ink.
// Run: swift tools/make_icon.swift <output_dir>
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

let ink    = NSColor(srgbRed: 0.09, green: 0.09, blue: 0.11, alpha: 1)
let accent = NSColor(srgbRed: 0.42, green: 0.55, blue: 1.00, alpha: 1)
let line   = NSColor(white: 0.97, alpha: 1)

func rr(_ r: CGRect, _ rad: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil)
}

func drawMark(_ cg: CGContext, _ rect: CGRect) {
    let w  = rect.width * 0.50
    let bw = rect.width * 0.075
    let gap = rect.width * 0.07
    let bh = rect.width * 0.36
    let t  = rect.width * 0.072
    let x0 = rect.midX - w / 2

    // Blockquote bar (accent), spanning the full mark height.
    cg.setFillColor(accent.cgColor)
    cg.addPath(rr(CGRect(x: x0, y: rect.midY - bh/2, width: bw, height: bh), bw/2)); cg.fillPath()

    // Two quoted text lines (white): top full-width, bottom shorter.
    let lx = x0 + bw + gap
    let lw = w - bw - gap
    cg.setFillColor(line.cgColor)
    // top line aligned to bar top
    cg.addPath(rr(CGRect(x: lx, y: rect.midY + bh/2 - t, width: lw, height: t), t/2)); cg.fillPath()
    // bottom line aligned to bar bottom (shorter)
    cg.addPath(rr(CGRect(x: lx, y: rect.midY - bh/2, width: lw * 0.66, height: t), t/2)); cg.fillPath()
}

func render(_ px: Int) -> Data {
    let size = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext

    let margin = size * 0.10
    let inner = size - margin * 2
    let rect = CGRect(x: margin, y: margin, width: inner, height: inner)
    let radius = inner * 0.2237

    cg.saveGState()
    cg.addPath(rr(rect, radius)); cg.clip()
    cg.setFillColor(ink.cgColor); cg.fill(rect)
    // very subtle top highlight for depth
    let space = CGColorSpaceCreateDeviceRGB()
    let g = CGGradient(colorsSpace: space,
        colors: [NSColor.white.withAlphaComponent(0.05).cgColor, NSColor.clear.cgColor] as CFArray,
        locations: [0, 1])!
    cg.drawLinearGradient(g, start: CGPoint(x: rect.midX, y: rect.maxY),
        end: CGPoint(x: rect.midX, y: rect.midY), options: [])
    cg.restoreGState()

    drawMark(cg, rect)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for s in [16, 32, 64, 128, 256, 512, 1024] {
    try! render(s).write(to: URL(fileURLWithPath: "\(outDir)/icon_\(s).png"))
    FileHandle.standardError.write("wrote icon_\(s).png\n".data(using: .utf8)!)
}
print("done")
