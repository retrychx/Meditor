// make_modern_icon.swift — MEditor 现代感图标候选：几何墨 / M 字母标 / 墨点。
// 品牌只保留两个载体：朱砂 #C0392B + 「墨/M」语义，去掉印章怀旧感。
// Run: swift tools/make_modern_icon.swift <output_dir>
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

let paper = NSColor(srgbRed: 0.957, green: 0.961, blue: 0.949, alpha: 1)
let ink   = NSColor(srgbRed: 0.106, green: 0.141, blue: 0.204, alpha: 1)
let seal  = NSColor(srgbRed: 0.753, green: 0.224, blue: 0.169, alpha: 1)
let white = NSColor(srgbRed: 0.995, green: 0.99,  blue: 0.985, alpha: 1)

func makeContext(_ px: Int) -> (NSBitmapImageRep, CGContext) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ctx
    return (rep, ctx.cgContext)
}

func finish(_ rep: NSBitmapImageRep) -> Data {
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

func rr(_ r: CGRect, _ rad: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil)
}

/// 满幅底 + 顶部圆角磁贴裁切（iOS 直接满幅即可，macOS 由 tile 函数处理）。
func fillBG(_ cg: CGContext, _ rect: CGRect, _ color: NSColor) {
    cg.setFillColor(color.cgColor); cg.fill(rect)
}

// MARK: - A. 几何墨：平底朱砂 + 大号几何无衬线「墨」
// 现代即时通讯类图标的打法：字即标，铺满、无装饰。
/// 按实际像素包围盒把「墨」绘制到画布正中（字体度量对 CJK 不可靠，直接量像素）。
func renderGeometricMo(_ px: Int) -> Data {
    let size = CGFloat(px)
    let font = NSFont(name: "PingFang SC Semibold", size: size * 0.50)
        ?? NSFont(name: "PingFang SC Medium", size: size * 0.50)
        ?? NSFont.boldSystemFont(ofSize: size * 0.50)

    // 第一遍：白底黑字画在任意位置，量字形实际像素包围盒
    let (measureRep, mcg) = makeContext(px)
    mcg.setFillColor(NSColor.white.cgColor)
    mcg.fill(CGRect(x: 0, y: 0, width: size, height: size))
    let probe = NSAttributedString(string: "墨", attributes: [.font: font, .foregroundColor: NSColor.black])
    probe.draw(at: .zero)
    NSGraphicsContext.restoreGraphicsState()
    guard let pixels = measureRep.bitmapData else { return Data() }
    var minX = px, minY = px, maxX = -1, maxY = -1
    let bpp = measureRep.bitsPerPixel / 8
    let bpr = measureRep.bytesPerRow
    for y in 0..<px {
        for x in 0..<px {
            let o = y * bpr + x * bpp
            if pixels[o] < 250 { // 非白 = 字形像素
                if x < minX { minX = x }; if x > maxX { maxX = x }
                if y < minY { minY = y }; if y > maxY { maxY = y }
            }
        }
    }

    // 第二遍：正式绘制，把包围盒中心对齐画布中心
    let (rep, cg) = makeContext(px)
    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    fillBG(cg, rect, seal)
    let str = NSAttributedString(string: "墨", attributes: [.font: font, .foregroundColor: white])
    let glyphW = CGFloat(maxX - minX), glyphH = CGFloat(maxY - minY)
    // 位图扫描坐标 y 向下，绘图坐标 y 向上：dx 直接算，dy 用翻转后的字形中心对齐画布中心
    let dx = (size - glyphW) / 2 - CGFloat(minX)
    let dy = CGFloat(minY + maxY) / 2 - size / 2
    str.draw(at: CGPoint(x: dx, y: dy))
    return finish(rep)
}

// MARK: - B. M 字母标：几何粗描边 M，末笔朱砂
func drawM(_ cg: CGContext, in rect: CGRect, side: CGFloat, main: NSColor, accent: NSColor) {
    let w = side, h = side * 0.78
    let x0 = rect.midX - w / 2, y0 = rect.midY - h / 2
    let sw = side * 0.135                     // 笔画宽
    cg.setLineCap(.round)
    cg.setLineJoin(.round)
    cg.setLineWidth(sw)

    // M 四笔：左竖、左斜、右斜、右竖（右竖朱砂）
    let leftX  = x0 + sw / 2
    let rightX = x0 + w - sw / 2
    let topY = y0 + sw / 2, botY = y0 + h - sw / 2
    let midX = x0 + w / 2
    let valleyY = y0 + h * 0.62

    cg.setStrokeColor(main.cgColor)
    let p1 = CGMutablePath()
    p1.move(to: CGPoint(x: leftX, y: botY)); p1.addLine(to: CGPoint(x: leftX, y: topY))
    p1.move(to: CGPoint(x: leftX, y: topY)); p1.addLine(to: CGPoint(x: midX, y: valleyY))
    p1.move(to: CGPoint(x: midX, y: valleyY)); p1.addLine(to: CGPoint(x: rightX, y: topY))
    cg.addPath(p1); cg.strokePath()

    cg.setStrokeColor(accent.cgColor)
    let p2 = CGMutablePath()
    p2.move(to: CGPoint(x: rightX, y: topY)); p2.addLine(to: CGPoint(x: rightX, y: botY))
    cg.addPath(p2); cg.strokePath()
}

func renderM(_ px: Int, bg: NSColor, main: NSColor) -> Data {
    let (rep, cg) = makeContext(px)
    let size = CGFloat(px)
    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    fillBG(cg, rect, bg)
    drawM(cg, in: rect, side: size * 0.52, main: main, accent: seal)
    return finish(rep)
}

// MARK: - C. 墨点：一枚朱砂圆点 + 一笔墨线（落款句点，画廊式极简）
func renderDot(_ px: Int) -> Data {
    let (rep, cg) = makeContext(px)
    let size = CGFloat(px)
    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    fillBG(cg, rect, paper)

    let d = size * 0.30
    let dotRect = CGRect(x: rect.midX - d / 2, y: rect.midY - size * 0.16 - d / 2, width: d, height: d)
    cg.setFillColor(seal.cgColor)
    cg.addEllipse(in: dotRect); cg.fillPath()

    // 下方一笔短墨线（收笔略细，手写感用圆头直线近似）
    cg.setStrokeColor(ink.cgColor)
    cg.setLineCap(.round)
    cg.setLineWidth(size * 0.055)
    let lineY = rect.midY + size * 0.16
    let p = CGMutablePath()
    p.move(to: CGPoint(x: rect.midX - size * 0.19, y: lineY))
    p.addLine(to: CGPoint(x: rect.midX + size * 0.19, y: lineY))
    cg.addPath(p); cg.strokePath()
    return finish(rep)
}

try! renderGeometricMo(1024).write(to: URL(fileURLWithPath: "\(outDir)/modern-A-geom-mo-1024.png"))
try! renderM(1024, bg: paper, main: ink).write(to: URL(fileURLWithPath: "\(outDir)/modern-B1-m-paper-1024.png"))
try! renderM(1024, bg: ink, main: white).write(to: URL(fileURLWithPath: "\(outDir)/modern-B2-m-ink-1024.png"))
try! renderDot(1024).write(to: URL(fileURLWithPath: "\(outDir)/modern-C-dot-1024.png"))
print("done → \(outDir)")
