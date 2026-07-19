import SwiftUI

// MARK: - Shared hero namespace (sidebar toggle flies toolbar ↔ sidebar card)

private struct SidebarToggleNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    var sidebarToggleNS: Namespace.ID? {
        get { self[SidebarToggleNamespaceKey.self] }
        set { self[SidebarToggleNamespaceKey.self] = newValue }
    }
}

extension View {
    /// Applies matchedGeometryEffect only when a namespace is available, so views
    /// in different subtrees can opt into a shared hero transition via environment.
    @ViewBuilder
    func heroMatch(_ id: String, in ns: Namespace.ID?) -> some View {
        if let ns {
            self.matchedGeometryEffect(id: id, in: ns)
        } else {
            self
        }
    }
}
