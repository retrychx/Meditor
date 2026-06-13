import Foundation
import Observation
import OSLog

/// Owns file-tree state and all related async operations.
///
/// AppState holds a reference and calls `reload(rootURL:)` / `scheduleWatchedReload(rootURL:)`
/// whenever the project root or FSEvents trigger a refresh. Views that only read
/// the file tree (FileSidebar, QuickOpen) can observe this manager directly if needed,
/// but for now AppState forwards its properties to keep the View layer unchanged.
@MainActor
@Observable
final class FileTreeManager {

    // MARK: - State

    var fileTree: [FileItem] = []
    var fileItemMap: [URL: FileItem] = [:]
    var indexedFiles: [FileItem] = []

    // MARK: - Private

    private let fileService: FileServiceProtocol

    @ObservationIgnored
    private var pendingReloadWork: DispatchWorkItem?

    @ObservationIgnored
    private var fileIndexGeneration = 0

    // MARK: - Init

    init(fileService: FileServiceProtocol) {
        self.fileService = fileService
    }

    // MARK: - Public API

    /// Immediately reload the first level of the tree and rebuild the full index.
    func reload(rootURL: URL) {
        let sid = PerformanceTracer.begin("ReloadFileTree", log: PerformanceTracer.fileOps)
        defer { PerformanceTracer.end("ReloadFileTree", log: PerformanceTracer.fileOps, id: sid) }

        pendingReloadWork?.cancel()
        fileItemMap = [:]
        let children = fileService.loadImmediateChildren(of: rootURL)
        fileTree = children
        addToMap(children)
        rebuildIndex(rootURL: rootURL)
    }

    /// Debounced reload triggered by FSEvents (200 ms coalesce).
    func scheduleWatchedReload(rootURL: URL) {
        pendingReloadWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.reload(rootURL: rootURL)
        }
        pendingReloadWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    /// Lazily load a directory's children on first expand.
    func loadChildrenIfNeeded(for item: FileItem) {
        guard item.isDirectory, !item.childrenLoaded, !item.isLoadingChildren else { return }
        item.isLoadingChildren = true
        let service = fileService
        let url = item.url
        Task.detached(priority: .userInitiated) { [weak self] in
            let children = service.loadImmediateChildren(of: url)
            await self?.applyLoadedChildren(children, to: item, expectedURL: url)
        }
    }

    /// Clear all tree state (called when a new folder is opened).
    func clear() {
        pendingReloadWork?.cancel()
        fileTree = []
        fileItemMap = [:]
        indexedFiles = []
        fileIndexGeneration &+= 1
    }

    // MARK: - URL Helpers

    func isSameOrDescendant(_ url: URL, of baseURL: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let basePath = baseURL.standardizedFileURL.path
        return path == basePath || path.hasPrefix(basePath + "/")
    }

    func replacingDescendantURL(_ url: URL, from oldBase: URL, to newBase: URL) -> URL? {
        let oldPath = oldBase.standardizedFileURL.path
        let srcPath = url.standardizedFileURL.path
        guard srcPath == oldPath || srcPath.hasPrefix(oldPath + "/") else { return nil }
        let suffix = srcPath.dropFirst(oldPath.count)
        guard !suffix.isEmpty else { return newBase.standardizedFileURL }
        return newBase.standardizedFileURL.appendingPathComponent(
            String(suffix.drop(while: { $0 == "/" }))
        )
    }

    // MARK: - Internal

    private func rebuildIndex(rootURL: URL) {
        let sid = PerformanceTracer.begin("RebuildFileIndex", log: PerformanceTracer.fileOps)
        fileIndexGeneration &+= 1
        let generation = fileIndexGeneration
        let service = fileService
        indexedFiles = []
        Task.detached(priority: .utility) { [weak self] in
            let files = service.loadAllFiles(under: rootURL)
            await self?.applyIndexedFiles(files, generation: generation, rootURL: rootURL)
            await MainActor.run {
                PerformanceTracer.end("RebuildFileIndex", log: PerformanceTracer.fileOps, id: sid)
            }
        }
    }

    private func applyLoadedChildren(_ children: [FileItem], to item: FileItem, expectedURL: URL) {
        guard item.url == expectedURL else { return }
        item.children = children
        item.childrenLoaded = true
        item.isLoadingChildren = false
        addToMap(children)
    }

    private func applyIndexedFiles(_ files: [FileItem], generation: Int, rootURL: URL) {
        guard generation == fileIndexGeneration else { return }
        indexedFiles = files
    }

    private func addToMap(_ items: [FileItem]) {
        for item in items {
            fileItemMap[item.id] = item
        }
    }
}
