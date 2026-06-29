import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Small convenience wrapper over the system pasteboard for plain-text copy.
enum Pasteboard {
    static func copy(_ string: String) {
#if os(macOS)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(string, forType: .string)
#else
        UIPasteboard.general.string = string
#endif
    }
}
