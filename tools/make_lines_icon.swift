// make_lines_icon.swift — 「线条」标识的 iOS 图标候选：纸底 + 朱砂竖条 + 松烟墨横条。
// 与 LaunchMark / macOS 图标同一几何语言，品牌色版本。
// Run: swift tools/make_lines_icon.swift <output_dir>
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

let paper = NSColor(srgbRed: 0.957, green: 0.961, blue: 0.949, alpha: 1)   // 宣纸白 #F4F5F2
let ink   = NSColor(srgbRed: 0.106, green: 0.141, blue: 0.204, alpha: 1)   // 松烟墨 #1B2434
let seal  = NSColor(srgbRed: 0.753, green: 0.224, blue: 0.169, alpha: 1)   // 朱砂 #C0392B

func rr(_ r: CGRect, _ rad: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil)
}

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ctx
    let cg = ctx.cgContext

    cg.setFillColor(paper.cgColor)
    cg.fill(CGRect(x: 0, y: 0, width: s, height: s))

    // 标识几何：与 macOS 图标同节奏 —— 左竖条 + 右两根横条（上长下短）
    let barW = s * 0.062
    let radius = barW / 2
    let leftX = s * 0.335
    let rightX = s * 0.475
    let centerY = s * 0.5
    let vH = s * 0.30
    let gap = s * 0.085  // 两横条与竖条的垂直节奏

    // 朱砂竖条
    cg.setFillColor(seal.cgColor)
    cg.addPath(rr(CGRect(x: leftX - barW/2, y: centerY - vH/2, width: barW, height: vH), radius)); cg.fillPath()

    // 上横条（长）
    let topH = barW
    let topY = centerY + gap
    cg.setFillColor(ink.cgColor)
    cg.addPath(rr(CGRect(x: rightX - barW/2, y: topY - topH/2, width: s * 0.27, height: topH), radius)); cg.fillPath()

    // 下横条（短）
    let botY = centerY - gap
    cg.addPath(rr(CGRect(x: rightX - barW/2, y: botY - topH/2, width: s * 0.185, height: topH), radius)); cg.fillPath()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

try! render(1024).write(to: URL(fileURLWithPath: "\(outDir)/lines-paper-ios-1024.png"))
print("done → \(outDir)")
