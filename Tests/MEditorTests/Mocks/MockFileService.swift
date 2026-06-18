import Foundation
@testable import MEditor

final class MockFileService: FileServiceProtocol {
    var fileExistsResult = true
    var readResult: String = "# Test"
    var readError: Error? = nil
    var writtenContent: String? = nil
    var createdFiles: [URL] = []
    var createdDirectories: [URL] = []
    var mockAttributes: [URL: [FileAttributeKey: Any]] = [:]

    func loadImmediateChildren(of directory: URL) -> [FileItem] { [] }
    func loadChildren(for item: FileItem) -> [FileItem] { [] }
    func loadAllFiles(under directory: URL) -> [FileItem] { [] }

    func readFile(at url: URL) throws -> String {
        if let error = readError { throw error }
        return readResult
    }

    func writeFile(at url: URL, content: String) throws {
        writtenContent = content
    }

    func createFile(at url: URL, content: String) throws {
        createdFiles.append(url)
    }

    func createDirectory(at url: URL) throws {
        createdDirectories.append(url)
    }

    func moveItem(from source: URL, to destination: URL) throws {}

    func removeItem(at url: URL) throws {}

    func fileExists(at url: URL) -> Bool { fileExistsResult }

    func fileExists(at url: URL, isDirectory: inout Bool) -> Bool {
        isDirectory = false
        return fileExistsResult
    }

    func attributes(at url: URL) -> [FileAttributeKey: Any]? {
        mockAttributes[url]
    }
}
