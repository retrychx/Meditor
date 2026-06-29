import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// A syntax highlighter that applies attributes to an NSTextStorage.
protocol SyntaxHighlightEngine {
    func highlight(text: String, into storage: NSTextStorage, range fullRange: NSRange, baseFont: PlatformFont)
}
