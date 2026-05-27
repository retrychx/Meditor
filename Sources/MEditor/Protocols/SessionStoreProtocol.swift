import Foundation

protocol SessionStoreProtocol {
    func scheduleSave(rootURL: URL?, openTabURLs: [URL], selectedIndex: Int?)
    func saveNow(rootURL: URL?, openTabURLs: [URL], selectedIndex: Int?)
    func load() -> SessionStore.PersistedSession?
    func clear()
}
