import Foundation

extension FileManager {
    /// First URL of a user-domain search-path directory, with a home-relative
    /// fallback so callers never need to force-unwrap (enforced by the
    /// force_unwrapping lint gate). These directories always exist in practice;
    /// the fallback is defensive only.
    func firstURL(for directory: SearchPathDirectory) -> URL {
        urls(for: directory, in: .userDomainMask).first
            ?? homeDirectoryForCurrentUser.appendingPathComponent(directory.fallbackPathComponent)
    }
}

private extension FileManager.SearchPathDirectory {
    var fallbackPathComponent: String {
        switch self {
        case .applicationSupportDirectory: return "Library/Application Support"
        case .cachesDirectory:             return "Library/Caches"
        case .documentDirectory:           return "Documents"
        default:                           return "Library"
        }
    }
}
