// make_icon_v3.swift — MEditor iOS 图标候选 v3，两个方向：
//   C: 光标 + 三行文本（更紧凑的段落感，去除 F 感）
//   D: 字标「墨」+ 朱砂印章小方（现代字标路线，字与章两个品牌资产合一）
// Run: swift tools/make_icon_v3.swift <output_dir>
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

let paper  = NSColor(srgbRed: 0.957, green: 0.961, blue: 0.949, alpha: 1)  // 宣纸白 #F4F5F2
let ink    = NSColor(srgbRed: 0.106, green: 0.141, blue: 0.204, alpha: 1)  // 松烟墨 #1B2434
let seal   = NSColor(srgbRed: 0.753, green: 0.224, blue: 0.169, alpha: 1)  // 朱砂 #C0392B

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

func flatTile(_ cg: CGContext, size: CGFloat, color: NSColor) {
    cg.setFillColor(color.cgColor)
    cg.fill(CGRect(x: 0, y: 0, width: size, height: size))
}

// MARK: - C：光标 + 三行文本

func renderC(_ px: Int) -> Data {
    let s = CGFloat(px)
    let (rep, cg) = canvas(px)
    flatTile(cg, size: s, color: ink)

    let stroke = s * 0.072
    let radius = stroke / 2
    // 三行文本：行距 = 0.9 笔画，宽度 1.0 / 0.78 / 0.56 递减
    let lineGap = stroke * 0.9
    let markH = stroke * 3 + lineGap * 2        // 文本块高
    let markW = s * 0.44
    let ox = (s - markW) / 2
    let oy = (s - markH) / 2
    let cursorGap = stroke * 0.62
    let lineX = ox + stroke + cursorGap
    let lineW = markW - stroke - cursorGap

    // 光标：与文本块同高
    cg.setFillColor(seal.cgColor)
    cg.addPath(rr(CGRect(x: ox, y: oy, width: stroke, height: markH), radius)); cg.fillPath()

    cg.setFillColor(paper.cgColor)
    let widths: [CGFloat] = [1.0, 0.78, 0.56]
    for (i, w) in widths.enumerated() {
        let y = oy + CGFloat(i) * (stroke + lineGap)
        cg.addPath(rr(CGRect(x: lineX, y: y, width: lineW * w, height: stroke), radius)); cg.fillPath()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

// MARK: - D：字标「墨」+ 朱砂印章小方

func renderD(_ px: Int) -> Data {
    let s = CGFloat(px)
    let (rep, cg) = canvas(px)
    flatTile(cg, size: s, color: ink)

    // 现代几何黑体的「墨」：逐级回退保证字体可用
    var font = NSFont.boldSystemFont(ofSize: s * 0.46)
    for name in ["PingFang SC Semibold", "PingFang SC Medium", "Hiragino Sans GB W6"] {
        if let f = NSFont(name: name, size: s * 0.46) { font = f; break }
    }
    let str = NSAttributedString(string: "墨", attributes: [
        .font: font,
        .foregroundColor: paper,
    ])
    // 用 CoreText 取字形实际墨迹包围盒（visual bounds），否则字体的
    // advance/leading 会让「整体居中」偏掉。
    let line = CTLineCreateWithAttributedString(str)
    let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)

    // 印章小方 = 落款：紧贴字标右下角，两者作为整体居中
    let sealSide = s * 0.115
    let sealGap = s * 0.035
    let totalW = bounds.width + sealGap + sealSide
    let glyphX = s * 0.5 - totalW / 2 - bounds.origin.x
    // 字的视觉重心略偏上，整体略下移补偿
    let glyphY = s * 0.5 - bounds.height / 2 - bounds.origin.y + s * 0.015
    // CTLineDraw 以 textPosition 为文字原点（基线起点），与 bounds 坐标系一致
    cg.textPosition = CGPoint(x: glyphX, y: glyphY)
    CTLineDraw(line, cg)

    // 落款印章：与字标墨迹的底部对齐，贴右下
    let sealRect = CGRect(x: glyphX + bounds.origin.x + bounds.width + sealGap,
                          y: glyphY + bounds.origin.y,
                          width: sealSide, height: sealSide)
    cg.setFillColor(seal.cgColor)
    cg.addPath(rr(sealRect, sealSide * 0.24)); cg.fillPath()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

try! renderC(1024).write(to: URL(fileURLWithPath: "\(outDir)/v3-cursor-1024.png"))
try! renderD(1024).write(to: URL(fileURLWithPath: "\(outDir)/v3-logotype-1024.png"))
print("done → \(outDir)")
