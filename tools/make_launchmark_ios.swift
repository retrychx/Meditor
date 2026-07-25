// make_launchmark_ios.swift — MEditor iOS 启动画面品牌图：透明底上的朱砂 blockquote 条 + 松烟墨双行。
// 几何比例与 tools/make_icon_ios.swift 的 drawMark 完全一致，启动画面与 App 图标共用同一个品牌符号；
// 换到宣纸底上时白线改为松烟墨（纸墨主题：纸面唯一的亮色是朱砂印）。
// Run: swift tools/make_launchmark_ios.swift <output_dir>
// 生成 launchmark@1x/@2x/@3x.png：192pt 画布（可见标记约 100x72pt），UILaunchScreen 居中显示。
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

let accent = NSColor(srgbRed: 0.753, green: 0.224, blue: 0.169, alpha: 1) // 朱砂 #C0392B
let ink    = NSColor(srgbRed: 0.106, green: 0.141, blue: 0.204, alpha: 1) // 松烟墨 #1B2434

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

    // Two quoted text lines (ink): top full-width, bottom shorter.
    let lx = x0 + bw + gap
    let lw = w - bw - gap
    cg.setFillColor(ink.cgColor)
    cg.addPath(rr(CGRect(x: lx, y: rect.midY + bh/2 - t, width: lw, height: t), t/2)); cg.fillPath()
    cg.addPath(rr(CGRect(x: lx, y: rect.midY - bh/2, width: lw * 0.66, height: t), t/2)); cg.fillPath()
}

for scale in 1...3 {
    let px = 192 * scale
    let size = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    // 透明底：只画标记，由 UILaunchScreen 的宣纸底色衬出。
    drawMark(ctx.cgContext, CGRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    let outPath = "\(outDir)/launchmark@\(scale)x.png"
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outPath))
    print("wrote \(outPath)")
}
