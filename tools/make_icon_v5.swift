// make_icon_v5.swift — MEditor iOS 图标候选 v5（纯图形，第二轮）。
//   A: 印章方 —— 纸底 + 一枚朱砂圆角方印，印章抽象到最纯粹的形式
//   B: 撇 —— 墨底 + 白色书法撇画（两端出锋）+ 朱砂小方
//   C: 墨滴 —— 墨底 + 白色垂墨滴 + 朱砂小方
// Run: swift tools/make_icon_v5.swift <output_dir>
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

// MARK: - A：印章方

/// bg == nil 时输出透明底（tinted 变体用：系统按 alpha 上用户色）。
func renderA(_ px: Int, bg: NSColor? = paper, tinted: Bool = false) -> Data {
    let s = CGFloat(px)
    let (rep, cg) = canvas(px, bg: bg ?? .clear)
    let side = s * 0.36
    let rect = CGRect(x: (s - side) / 2, y: (s - side) / 2, width: side, height: side)
    // 微斜 3°：钤印落下的那一瞬
    cg.saveGState()
    cg.translateBy(x: rect.midX, y: rect.midY)
    cg.rotate(by: -3 * .pi / 180)
    cg.translateBy(x: -rect.midX, y: -rect.midY)
    if tinted {
        // tinted：中性灰单色，不做光影（系统上色时保留灰度层次）
        cg.setFillColor(NSColor(white: 0.55, alpha: 1).cgColor)
        cg.addPath(rr(rect, side * 0.22)); cg.fillPath()
        cg.restoreGState()
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])!
    }
    // 软影：印泥压上纸面的微微起伏
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -side * 0.02), blur: side * 0.06,
                 color: NSColor.black.withAlphaComponent(0.18).cgColor)
    cg.setFillColor(seal.cgColor)
    cg.addPath(rr(rect, side * 0.22)); cg.fillPath()
    cg.restoreGState()
    // 章体 + 顶部一线亮部（印泥光泽）
    cg.saveGState()
    cg.addPath(rr(rect, side * 0.22)); cg.clip()
    cg.setFillColor(seal.cgColor); cg.fill(rect)
    let sealHi = NSColor(srgbRed: 0.835, green: 0.310, blue: 0.235, alpha: 1)
    let space = CGColorSpaceCreateDeviceRGB()
    let g = CGGradient(colorsSpace: space,
        colors: [sealHi.withAlphaComponent(0.55).cgColor, NSColor.clear.cgColor] as CFArray,
        locations: [0, 0.45])!
    cg.drawLinearGradient(g, start: CGPoint(x: rect.midX, y: rect.maxY),
        end: CGPoint(x: rect.midX, y: rect.midY), options: [])
    cg.restoreGState()
    cg.restoreGState()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

// MARK: - B：撇

/// 书法撇画：起笔粗、收笔出锋的月牙形。
/// 用内外两条二次曲线合成，两端收尖。
func brushStrokePath(cx: CGFloat, cy: CGFloat, len: CGFloat, width: CGFloat, angle: CGFloat) -> CGPath {
    let path = CGMutablePath()
    // 沿主轴的局部坐标：从 (-len/2, 0) 到 (len/2, 0)
    // 外弧（上凸）与内弧（下凹）围成月牙，两端尖。
    path.move(to: CGPoint(x: -len / 2, y: 0))
    // 外弧（起笔一侧略饱满）
    path.addQuadCurve(to: CGPoint(x: len / 2, y: 0),
                      control: CGPoint(x: -len * 0.08, y: width * 1.05))
    // 内弧
    path.addQuadCurve(to: CGPoint(x: -len / 2, y: 0),
                      control: CGPoint(x: len * 0.10, y: -width * 0.42))
    path.closeSubpath()

    var t = CGAffineTransform(translationX: cx, y: cy).rotated(by: angle)
    return path.copy(using: &t) ?? path
}

func renderB(_ px: Int) -> Data {
    let s = CGFloat(px)
    let (rep, cg) = canvas(px, bg: ink)

    // 撇：中心略偏左上，约 -52°
    cg.setFillColor(paper.cgColor)
    cg.addPath(brushStrokePath(cx: s * 0.47, cy: s * 0.52, len: s * 0.52, width: s * 0.17,
                               angle: -52 * .pi / 180))
    cg.fillPath()

    // 朱砂小方：收锋方向的落款位
    let side = s * 0.10
    cg.setFillColor(seal.cgColor)
    cg.addPath(rr(CGRect(x: s * 0.68, y: s * 0.20, width: side, height: side), side * 0.24))
    cg.fillPath()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

// MARK: - C：墨滴

/// 垂落的墨滴：圆身 + 顶部收尖（水滴剪影）。
func inkDropPath(cx: CGFloat, cy: CGFloat, r: CGFloat) -> CGPath {
    let path = CGMutablePath()
    // 顶部尖点
    let tip = CGPoint(x: cx, y: cy + r * 1.9)
    path.move(to: tip)
    // 左右两条三次曲线收成圆身
    path.addCurve(to: CGPoint(x: cx - r, y: cy),
                  control1: CGPoint(x: cx - r * 0.10, y: cy + r * 1.15),
                  control2: CGPoint(x: cx - r, y: cy + r * 0.85))
    path.addArc(center: CGPoint(x: cx, y: cy), radius: r,
                startAngle: .pi, endAngle: 0, clockwise: false)
    path.addCurve(to: tip,
                  control1: CGPoint(x: cx + r, y: cy + r * 0.85),
                  control2: CGPoint(x: cx + r * 0.10, y: cy + r * 1.15))
    path.closeSubpath()
    return path
}

func renderC(_ px: Int) -> Data {
    let s = CGFloat(px)
    let (rep, cg) = canvas(px, bg: ink)

    cg.setFillColor(paper.cgColor)
    cg.addPath(inkDropPath(cx: s * 0.47, cy: s * 0.46, r: s * 0.20))
    cg.fillPath()

    let side = s * 0.10
    cg.setFillColor(seal.cgColor)
    cg.addPath(rr(CGRect(x: s * 0.66, y: s * 0.24, width: side, height: side), side * 0.24))
    cg.fillPath()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

try! renderA(1024).write(to: URL(fileURLWithPath: "\(outDir)/v5-seal-1024.png"))
try! renderA(1024, bg: ink).write(to: URL(fileURLWithPath: "\(outDir)/v5-seal-dark-1024.png"))
try! renderA(1024, bg: nil, tinted: true).write(to: URL(fileURLWithPath: "\(outDir)/v5-seal-tinted-1024.png"))
try! renderB(1024).write(to: URL(fileURLWithPath: "\(outDir)/v5-stroke-1024.png"))
try! renderC(1024).write(to: URL(fileURLWithPath: "\(outDir)/v5-drop-1024.png"))
print("done → \(outDir)")
