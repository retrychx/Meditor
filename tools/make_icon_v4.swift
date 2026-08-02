// make_icon_v4.swift — MEditor iOS 图标候选 v4（纯图形，无文字）。
//   A: 墨锭 · 纸底 —— 徽墨造型：松烟墨条 + 顶端朱砂印（文化意象，最简几何）
//   B: 墨锭 · 墨底 —— 宣纸白墨条 + 朱砂印
//   C: 纸 + 光标 · 墨底 —— 抽象文档：纸白圆角页 + 朱砂光标条
// Run: swift tools/make_icon_v4.swift <output_dir>
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

let paper = NSColor(srgbRed: 0.957, green: 0.961, blue: 0.949, alpha: 1)  // 宣纸白 #F4F5F2
let ink   = NSColor(srgbRed: 0.106, green: 0.141, blue: 0.204, alpha: 1)  // 松烟墨 #1B2434
let seal  = NSColor(srgbRed: 0.753, green: 0.224, blue: 0.169, alpha: 1)  // 朱砂 #C0392B

func rr(_ r: CGRect, _ rad: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil)
}

func canvas(_ px: Int, bg: NSColor) -> (NSBitmapImageRep, CGContext) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ctx
    let cg = ctx.cgContext
    cg.setFillColor(bg.cgColor)
    cg.fill(CGRect(x: 0, y: 0, width: CGFloat(px), height: CGFloat(px)))
    return (rep, cg)
}

/// 墨锭：竖直墨条 + 顶部朱砂印。stick 色与 bg 对比。
func drawInkStick(_ cg: CGContext, s: CGFloat, stick: NSColor) {
    let stickW = s * 0.155
    let stickH = s * 0.52
    let rect = CGRect(x: (s - stickW) / 2, y: (s - stickH) / 2 - s * 0.01, width: stickW, height: stickH)
    cg.setFillColor(stick.cgColor)
    cg.addPath(rr(rect, stickW * 0.28)); cg.fillPath()

    // 朱砂印：嵌在墨条顶部（徽墨的红印/描金位），宽度占墨条 2/3
    let sealSide = stickW * 0.62
    let sealRect = CGRect(x: rect.midX - sealSide / 2,
                          y: rect.maxY - stickH * 0.09 - sealSide,
                          width: sealSide, height: sealSide)
    cg.setFillColor(seal.cgColor)
    cg.addPath(rr(sealRect, sealSide * 0.22)); cg.fillPath()
}

func renderA(_ px: Int) -> Data {   // 墨锭 · 纸底
    let s = CGFloat(px)
    let (rep, cg) = canvas(px, bg: paper)
    drawInkStick(cg, s: s, stick: ink)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

func renderB(_ px: Int) -> Data {   // 墨锭 · 墨底
    let s = CGFloat(px)
    let (rep, cg) = canvas(px, bg: ink)
    drawInkStick(cg, s: s, stick: paper)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

func renderC(_ px: Int) -> Data {   // 纸 + 光标 · 墨底
    let s = CGFloat(px)
    let (rep, cg) = canvas(px, bg: ink)

    // 纸页：微圆角竖版矩形，略偏右，给光标留位
    let pageW = s * 0.40
    let pageH = s * 0.50
    let page = CGRect(x: s * 0.5 - pageW * 0.42, y: (s - pageH) / 2, width: pageW, height: pageH)
    cg.setFillColor(paper.cgColor)
    cg.addPath(rr(page, s * 0.055)); cg.fillPath()

    // 光标：朱砂竖条，探出纸页左缘（正在书写的一瞬）
    let curW = s * 0.055
    let curH = s * 0.22
    let cur = CGRect(x: page.minX - curW * 0.55, y: page.maxY - pageH * 0.30 - curH, width: curW, height: curH)
    cg.setFillColor(seal.cgColor)
    cg.addPath(rr(cur, curW / 2)); cg.fillPath()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

try! renderA(1024).write(to: URL(fileURLWithPath: "\(outDir)/v4-stick-paper-1024.png"))
try! renderB(1024).write(to: URL(fileURLWithPath: "\(outDir)/v4-stick-ink-1024.png"))
try! renderC(1024).write(to: URL(fileURLWithPath: "\(outDir)/v4-page-cursor-1024.png"))
print("done → \(outDir)")
