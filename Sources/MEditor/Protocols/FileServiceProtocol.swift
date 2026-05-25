import Foundation

protocol FileServiceProtocol: AnyObject {
    func loadImmediateChildren(of directory: URL) -> [FileItem]
    func loadChildren(for item: FileItem) -> [FileItem]
    func readFile(at url: URL) throws -> String
    func writeFile(at url: URL, content: String) throws
}
