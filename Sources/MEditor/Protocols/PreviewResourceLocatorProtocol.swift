import Foundation

protocol PreviewResourceLocatorProtocol {
    var resourceBaseURL: URL? { get }
    func cssURL(named name: String) -> URL?
    func jsURL(named name: String) -> URL?
}
