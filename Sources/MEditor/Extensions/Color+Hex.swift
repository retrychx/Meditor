import SwiftUI

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

    /// Convert a SwiftUI Color to a lowercase CSS hex string (#rrggbb).
    func hexString() -> String {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return "#000000" }
        let r = Int(max(0, min(1, c.redComponent))   * 255)
        let g = Int(max(0, min(1, c.greenComponent)) * 255)
        let b = Int(max(0, min(1, c.blueComponent))  * 255)
        return String(format: "#%02x%02x%02x", r, g, b)
    }

    /// App-wide accent that honors the user's accent-style preference
    /// (`MEditor.aiAccentStyle`: "system" or "shadcn"). For "shadcn" it resolves
    /// to a mono near-black (#18181B) in light mode / near-white (#FAFAFA) in dark
    /// mode; otherwise it falls back to the system accent. Used everywhere the app
    /// draws its own accent so the choice applies globally, not just to controls.
    static var appAccent: Color {
        let raw = UserDefaults.standard.string(forKey: "MEditor.aiAccentStyle") ?? "system"
        guard raw == "shadcn" else { return .accentColor }
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(white: 0.98, alpha: 1)                              // #FAFAFA
                : NSColor(red: 0.094, green: 0.094, blue: 0.106, alpha: 1)    // #18181B
        })
    }
}
