import SwiftUI

// MARK: - 平台替身（Shims）
//
// 共享代码 Models/AIModels.swift 的 AIAccentStyle 引用 macOS 端的
// PreviewTheme（Models/PreviewTheme.swift）与 Color(hex:)（Extensions/Color+Hex.swift）。
// 这两个文件依赖 NSColor，无法编进 iOS target；这里提供移动端最小替身，
// 只覆盖 AIAccentStyle 实际用到的成员（isDark / Color(hex:)）。

enum PreviewTheme: String, CaseIterable, Identifiable {
    case github

    var id: String { rawValue }
    var displayName: String { "GitHub" }
    var isDark: Bool { false }
}

extension Color {
    /// Initialize a SwiftUI Color from a CSS hex string (#RGB or #RRGGBB).
    init(hex: String) {
        var s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        let v = UInt64(s, radix: 16) ?? 0
        self.init(
            red:   Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8)  & 0xFF) / 255,
            blue:  Double( v        & 0xFF) / 255
        )
    }
}
