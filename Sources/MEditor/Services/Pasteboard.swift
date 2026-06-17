import AppKit

/// Small convenience wrapper over `NSPasteboard.general` for plain-text copy.
enum Pasteboard {
    static func copy(_ string: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(string, forType: .string)
    }
}
