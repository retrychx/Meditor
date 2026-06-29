import Foundation

/// Locates static preview resources (HTML template, CSS, JS) bundled with
/// the application, regardless of whether the binary runs from a SwiftPM
/// resource bundle (debug) or a packaged `.app`.
///
/// Centralizing this logic avoids relying on `Bundle.module`, which can
/// crash if the SwiftPM-generated bundle lacks an Info.plist.
enum PreviewResourceLocator {

    /// Returns the directory containing `template.html`, `css/`, `scripts/` etc.
    /// Returns nil if no candidate location yields the template file.
    static func resourcesRoot() -> URL? {
        let fm = FileManager.default
        let mainURL = Bundle.main.bundleURL

        // Candidate locations, in order of preference:
        let candidates: [URL] = [
            // 1. SwiftPM resource bundle next to executable (debug builds)
            mainURL.appendingPathComponent("MEditor_MEditor.bundle/Resources/Preview"),
            // 2. Packaged .app bundle: Contents/Resources/Preview
            mainURL.appendingPathComponent("Contents/Resources/Preview"),
            // 3. Direct sibling Preview directory
            mainURL.appendingPathComponent("Preview"),
        ]

        for url in candidates {
            let templateURL = url.appendingPathComponent("template.html")
            if fm.fileExists(atPath: templateURL.path) {
                return url
            }
        }
        return nil
    }

    /// Returns the URL of `template.html`, or nil if not found.
    static func templateURL() -> URL? {
        return resourcesRoot()?.appendingPathComponent("template.html")
    }
}
