import Foundation
@testable import MEditor

class MockFileService: FileServiceProtocol {
    var fileExistsResult = true
    var readResult: String = "# Test"
    var readError: Error? = nil
    var writtenContent: String? = nil
    var createdFiles: [URL] = []
    var createdDirectories: [URL] = []
    var mockAttributes: [URL: [FileAttributeKey: Any]] = [:]
    private var files: [URL: String] = [:]
    private var children: [URL: [FileItem]] = [:]
    private let lock = NSLock()

    func setFile(_ url: URL, content: String) {
        lock.lock()
        files[url] = content
        lock.unlock()
    }

    func fileContent(at url: URL) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return files[url]
    }

    func setChildren(_ items: [FileItem], for directory: URL) {
        lock.lock()
        children[directory] = items
        lock.unlock()
    }

    func loadImmediateChildren(of directory: URL) -> [FileItem] {
        lock.lock()
        defer { lock.unlock() }
        return children[directory] ?? []
    }

    func loadChildren(for item: FileItem) -> [FileItem] {
        lock.lock()
        let childs = children[item.url] ?? []
        lock.unlock()
        item.children = childs
        return childs
    }

    func loadAllFiles(under directory: URL) -> [FileItem] {
        lock.lock()
        defer { lock.unlock() }
        return children[directory] ?? []
    }

    func loadAllItems(under directory: URL) -> [FileItem] {
        lock.lock()
        defer { lock.unlock() }
        return children[directory] ?? []
    }

    func readFile(at url: URL) throws -> String {
        if let error = readError { throw error }
        if let content = fileContent(at: url) { return content }
        return readResult
    }

    func writeFile(at url: URL, content: String) throws {
        writtenContent = content
        setFile(url, content: content)
    }

    func createFile(at url: URL, content: String) throws {
        createdFiles.append(url)
        setFile(url, content: content)
    }

    func createDirectory(at url: URL) throws {
        createdDirectories.append(url)
    }

    func moveItem(from source: URL, to destination: URL) throws {
        lock.lock()
        if let content = files[source] {
            files[destination] = content
            files.removeValue(forKey: source)
        }
        lock.unlock()
    }

    func removeItem(at url: URL) throws {
        lock.lock()
        files.removeValue(forKey: url)
        lock.unlock()
    }

    func fileExists(at url: URL) -> Bool {
        if fileContent(at: url) != nil { return true }
        if mockAttributes[url] != nil || children[url] != nil { return true }
        if FileManager.default.fileExists(atPath: url.path) { return true }
        return fileExistsResult
    }

    func fileExists(at url: URL, isDirectory: inout Bool) -> Bool {
        if fileContent(at: url) != nil || mockAttributes[url] != nil {
            isDirectory = false
            return true
        }
        if children[url] != nil {
            isDirectory = true
            return true
        }
        var realIsDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &realIsDir) {
            isDirectory = realIsDir.boolValue
            return true
        }
        isDirectory = false
        return fileExistsResult
    }

    func attributes(at url: URL) -> [FileAttributeKey: Any]? {
        if let attrs = mockAttributes[url] { return attrs }
        if let content = fileContent(at: url) { return [.size: Int64(content.utf8.count)] }
        return try? FileManager.default.attributesOfItem(atPath: url.path)
    }
}
