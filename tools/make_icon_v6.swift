// make_icon_v6.swift — MEditor iOS 图标候选 v6：质感黑底 + 设计感 M + 小朱砂印。
//   A: 几何 M —— 直线骨架 + 圆角接头，现代极简
//   B: 拱桥 M —— 双拱连续曲线，柔和有识别度
//   C: 书法 M —— 四笔带锋笔触，呼应「墨」
// Run: swift tools/make_icon_v6.swift <output_dir>
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

let paper = NSColor(srgbRed: 0.957, green: 0.961, blue: 0.949, alpha: 1)  // 宣纸白 #F4F5F2
let seal  = NSColor(srgbRed: 0.753, green: 0.224, blue: 0.169, alpha: 1)  // 朱砂 #C0392B

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

/// 质感黑底：墨蓝纵向渐变 + 四角暗角（vignette），不是死黑。
func paintBlackGround(_ cg: CGContext, s: CGFloat) {
    let space = CGColorSpaceCreateDeviceRGB()
    let top = NSColor(srgbRed: 0.145, green: 0.180, blue: 0.247, alpha: 1)  // #253049-ish
    let bot = NSColor(srgbRed: 0.072, green: 0.094, blue: 0.137, alpha: 1)  // #121823
    let g = CGGradient(colorsSpace: space, colors: [top.cgColor, bot.cgColor] as CFArray,
                       locations: [0, 1])!
    cg.drawLinearGradient(g, start: CGPoint(x: s * 0.3, y: s), end: CGPoint(x: s * 0.7, y: 0), options: [])
    // 暗角：中心透明 → 边缘 16% 黑（轻压角即可，别吃掉底色的蓝）
    let vignette = CGGradient(colorsSpace: space,
        colors: [NSColor.clear.cgColor, NSColor.black.withAlphaComponent(0.16).cgColor] as CFArray,
        locations: [0.55, 1])!
    cg.drawRadialGradient(vignette,
        startCenter: CGPoint(x: s/2, y: s/2), startRadius: 0,
        endCenter: CGPoint(x: s/2, y: s/2), endRadius: s * 0.72,
        options: .drawsAfterEndLocation)
}

/// 小朱砂印：右下角落款位。
func drawTinySeal(_ cg: CGContext, s: CGFloat) {
    let side = s * 0.07
    cg.setFillColor(seal.cgColor)
    cg.addPath(rr(CGRect(x: s * 0.715, y: s * 0.225, width: side, height: side), side * 0.26))
    cg.fillPath()
}

// MARK: - A：几何 M

func renderA(_ px: Int) -> Data {
    let s = CGFloat(px)
    let (rep, cg) = canvas(px)
    paintBlackGround(cg, s: s)

    let w = s * 0.085
    let x0 = s * 0.28 + w/2, x1 = s * 0.72 - w/2
    // Quartz 是 y 向上：视觉上的「顶」是大 y
    let yTop = s * 0.68 - w/2, yBot = s * 0.32 + w/2
    let xMid = (x0 + x1) / 2
    let yValley = yBot + (yTop - yBot) * 0.12   // 中谷近乎到底，才是 M 不是 W

    let path = CGMutablePath()
    path.move(to: CGPoint(x: x0, y: yBot))
    path.addLine(to: CGPoint(x: x0, y: yTop))
    path.addLine(to: CGPoint(x: xMid, y: yValley))
    path.addLine(to: CGPoint(x: x1, y: yTop))
    path.addLine(to: CGPoint(x: x1, y: yBot))

    cg.setStrokeColor(paper.cgColor)
    cg.setLineWidth(w)
    cg.setLineCap(.round)
    cg.setLineJoin(.round)
    cg.addPath(path)
    cg.strokePath()

    drawTinySeal(cg, s: s)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

// MARK: - B：拱桥 M

func renderB(_ px: Int) -> Data {
    let s = CGFloat(px)
    let (rep, cg) = canvas(px)
    paintBlackGround(cg, s: s)

    let w = s * 0.088
    let x0 = s * 0.27 + w/2, x1 = s * 0.73 - w/2
    let xMid = (x0 + x1) / 2
    let yBot = s * 0.70 - w/2
    let yApex = s * 0.30 + w/2

    let path = CGMutablePath()
    path.move(to: CGPoint(x: x0, y: yBot))
    // 左拱：控制点在左半上方，形成抛物拱
    path.addQuadCurve(to: CGPoint(x: xMid, y: yBot),
                      control: CGPoint(x: x0 - (xMid - x0) * 0.18, y: yApex - (yBot - yApex) * 0.22))
    // 右拱
    path.addQuadCurve(to: CGPoint(x: x1, y: yBot),
                      control: CGPoint(x: x1 + (x1 - xMid) * 0.18, y: yApex - (yBot - yApex) * 0.22))

    cg.setStrokeColor(paper.cgColor)
    cg.setLineWidth(w)
    cg.setLineCap(.round)
    cg.addPath(path)
    cg.strokePath()

    drawTinySeal(cg, s: s)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

// MARK: - C：书法 M

/// 两端出锋的笔形（梭形）：主轴 len，最宽 width。
func brushLens(cx: CGFloat, cy: CGFloat, len: CGFloat, width: CGFloat, angle: CGFloat) -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: -len / 2, y: 0))
    path.addQuadCurve(to: CGPoint(x: len / 2, y: 0),
                      control: CGPoint(x: 0, y: width * 0.62))
    path.addQuadCurve(to: CGPoint(x: -len / 2, y: 0),
                      control: CGPoint(x: 0, y: -width * 0.62))
    path.closeSubpath()
    var t = CGAffineTransform(translationX: cx, y: cy).rotated(by: angle)
    return path.copy(using: &t) ?? path
}

func renderC(_ px: Int, tinted: Bool = false) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ctx
    let cg = ctx.cgContext
    if tinted {
        // tinted 变体：透明底 + 中性灰单色（系统按 alpha 上用户色）
        cg.clear(CGRect(x: 0, y: 0, width: s, height: s))
    } else {
        paintBlackGround(cg, s: s)
    }

    cg.setFillColor(tinted ? NSColor(white: 0.55, alpha: 1).cgColor : paper.cgColor)
    let stemW = s * 0.098
    // 关键点位：四笔在关节处咬合（左顶角 / 中谷底 / 右顶角）
    let xL = s * 0.295, xR = s * 0.705, xM = s * 0.5
    let yTop = s * 0.315, yBot = s * 0.685, yValley = s * 0.63
    let stemLen = yBot - yTop + stemW * 0.6
    let stemCY = (yTop + yBot) / 2
    // 左竖（起笔在上出锋，略向左倾）
    cg.addPath(brushLens(cx: xL, cy: stemCY, len: stemLen, width: stemW,
                         angle: -.pi / 2 + 0.05))
    // 右竖（收笔在下出锋，略向右倾）
    cg.addPath(brushLens(cx: xR, cy: stemCY, len: stemLen, width: stemW,
                         angle: -.pi / 2 - 0.05))
    // 左斜（左顶角 → 中谷底）：中心取两点中点，角度取连线方向
    let dlCx = (xL + xM) / 2, dlCy = (yTop + yValley) / 2
    let dlLen = hypot(xM - xL, yValley - yTop) + stemW * 0.2
    let dlAngle = -atan2(yValley - yTop, xM - xL)
    cg.addPath(brushLens(cx: dlCx, cy: dlCy, len: dlLen, width: stemW * 0.92,
                         angle: dlAngle))
    // 右斜（中谷底 → 右顶角）
    let drCx = (xM + xR) / 2, drCy = (yValley + yTop) / 2
    let drLen = hypot(xR - xM, yValley - yTop) + stemW * 0.2
    let drAngle = -atan2(yTop - yValley, xR - xM)
    cg.addPath(brushLens(cx: drCx, cy: drCy, len: drLen, width: stemW * 0.92,
                         angle: drAngle))
    cg.fillPath()

    if !tinted {
        drawTinySeal(cg, s: s)
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

try! renderA(1024).write(to: URL(fileURLWithPath: "\(outDir)/v6-geo-1024.png"))
try! renderB(1024).write(to: URL(fileURLWithPath: "\(outDir)/v6-arch-1024.png"))
try! renderC(1024).write(to: URL(fileURLWithPath: "\(outDir)/v6-brush-1024.png"))
try! renderC(1024, tinted: true).write(to: URL(fileURLWithPath: "\(outDir)/v6-brush-tinted-1024.png"))
print("done → \(outDir)")
