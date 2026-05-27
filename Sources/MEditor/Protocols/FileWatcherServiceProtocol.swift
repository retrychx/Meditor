import Foundation

protocol FileWatcherServiceProtocol {
    func startWatching(urls: [URL], onChange: @escaping () -> Void)
    func stopWatching()
}
