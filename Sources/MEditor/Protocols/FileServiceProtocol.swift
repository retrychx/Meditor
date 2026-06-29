import Foundation

protocol FileServiceProtocol: AnyObject {
    // Directory scanning
    func loadImmediateChildren(of directory: URL) -> [FileItem]
    func loadChildren(for item: FileItem) -> [FileItem]
    func loadAllFiles(under directory: URL) -> [FileItem]
    func loadAllItems(under directory: URL) -> [FileItem]

    // File I/O
    func readFile(at url: URL) throws -> String
    func writeFile(at url: URL, content: String) throws

    // Filesystem operations
    func createFile(at url: URL, content: String) throws
    func createDirectory(at url: URL) throws
    func moveItem(from source: URL, to destination: URL) throws
    func removeItem(at url: URL) throws
    func fileExists(at url: URL) -> Bool
    func fileExists(at url: URL, isDirectory: inout Bool) -> Bool
    func attributes(at url: URL) -> [FileAttributeKey: Any]?
}
