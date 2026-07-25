import SwiftUI

/// 阅读设置：字号 / 行距档位，UserDefaults 持久化。
/// Markdown 预览的正文 / 标题 / 代码按系数缩放，编辑态等宽字号跟随；
/// 行距系数作用于预览各行距（HTML 预览不管）。
@Observable
final class ReaderSettings {
    /// 字号档位：基准 17pt 正文的缩放系数。
    enum FontScale: Double, CaseIterable, Identifiable {
        case small = 0.85
        case standard = 1.0
        case large = 1.15
        case xlarge = 1.3

        var id: Double { rawValue }

        var displayName: String {
            switch self {
            case .small:    return "小"
            case .standard: return "标准"
            case .large:    return "大"
            case .xlarge:   return "特大"
            }
        }
    }

    /// 行距档位：行高 / 字号 的倍率（紧凑 1.2 / 标准 1.5 / 宽松 1.8）。
    enum LineSpacing: Double, CaseIterable, Identifiable {
        case compact = 1.2
        case standard = 1.5
        case relaxed = 1.8

        var id: Double { rawValue }

        var displayName: String {
            switch self {
            case .compact:  return "紧凑"
            case .standard: return "标准"
            case .relaxed:  return "宽松"
            }
        }
    }

    private static let fontScaleKey = "readerFontScale"
    private static let lineSpacingKey = "readerLineSpacing"

    var fontScale: FontScale {
        didSet { UserDefaults.standard.set(fontScale.rawValue, forKey: Self.fontScaleKey) }
    }
    var lineSpacing: LineSpacing {
        didSet { UserDefaults.standard.set(lineSpacing.rawValue, forKey: Self.lineSpacingKey) }
    }

    init() {
        let defaults = UserDefaults.standard
        let scaleRaw = defaults.double(forKey: Self.fontScaleKey)
        let spacingRaw = defaults.double(forKey: Self.lineSpacingKey)
        fontScale = FontScale(rawValue: scaleRaw) ?? .standard
        lineSpacing = LineSpacing(rawValue: spacingRaw) ?? .standard
    }

    /// 字号系数缩放后的点字号。
    func scaled(_ base: CGFloat) -> CGFloat {
        base * scaleFactor
    }

    /// 字号系数（CGFloat）：Typography 的 scaledBy / 编辑器字号直接用。
    var scaleFactor: CGFloat { CGFloat(fontScale.rawValue) }

    /// SwiftUI lineSpacing（行间附加留白）：字号 ×（行距倍率 − 1）。
    func lineGap(for size: CGFloat) -> CGFloat {
        size * CGFloat(lineSpacing.rawValue - 1)
    }
}
