import Foundation

extension FileManager {
    /// First URL of a user-domain search-path directory, with a defensive
    /// fallback so callers never need to force-unwrap (enforced by the
    /// force_unwrapping lint gate). These directories always exist in practice
    /// (iOS app sandbox guarantees them); the fallback is defense in depth and
    /// deliberately uses NSTemporaryDirectory() because it exists on both
    /// platforms — homeDirectoryForCurrentUser is macOS-only.
    func firstURL(for directory: SearchPathDirectory) -> URL {
        urls(for: directory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
    }
}
