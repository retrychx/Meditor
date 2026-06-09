import Foundation

enum FilePathFormatter {
    static func relativePath(for url: URL, rootURL: URL?) -> String {
        let targetURL = url.standardizedFileURL
        guard let rootURL = rootURL?.standardizedFileURL else {
            return targetURL.path
        }

        let rootPath = rootURL.path
        let targetPath = targetURL.path
        guard targetPath == rootPath || targetPath.hasPrefix(rootPath + "/") else {
            return targetPath
        }

        let suffix = targetPath.dropFirst(rootPath.count)
        let relativePath = String(suffix.drop(while: { $0 == "/" }))
        return relativePath.isEmpty ? "." : relativePath
    }
}
