import Foundation

/// Breaks feedback loops between editor-driven, preview-driven, and TOC-driven
/// scroll sync by dropping the next echoed callback from the opposite side.
struct ScrollSyncState {
    private(set) var suppressNextPreviewEcho = false
    private(set) var suppressNextEditorEcho = false

    mutating func registerTOCNavigation() {
        suppressNextPreviewEcho = true
        suppressNextEditorEcho = true
    }

    mutating func shouldPropagateEditorScroll() -> Bool {
        if suppressNextEditorEcho {
            suppressNextEditorEcho = false
            return false
        }
        suppressNextPreviewEcho = true
        return true
    }

    mutating func shouldPropagatePreviewScroll() -> Bool {
        if suppressNextPreviewEcho {
            suppressNextPreviewEcho = false
            return false
        }
        suppressNextEditorEcho = true
        return true
    }
}
