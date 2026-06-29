import Observation
import SwiftUI

enum ActiveMainView {
    case document, todos, calendar
}

@MainActor
@Observable
final class WorkspaceUIState {
    var showsSidebar: Bool {
        didSet { AppSettings.shared.showSidebarOnLaunch = showsSidebar }
    }

    var showsEditor: Bool {
        didSet { AppSettings.shared.showEditorOnLaunch = showsEditor }
    }

    var showsPreview: Bool {
        didSet { AppSettings.shared.showPreviewOnLaunch = showsPreview }
    }

    var sidebarWidth: CGFloat
    var isFocusMode = false
    var activeMainView: ActiveMainView = .document
    var expandedPaths: Set<String> = {
        Set(UserDefaults.standard.stringArray(forKey: "sidebar.expandedPaths") ?? [])
    }()

    func setExpanded(_ item: FileItem, _ expanded: Bool) {
        if expanded { expandedPaths.insert(item.url.path) }
        else { expandedPaths.remove(item.url.path) }
        UserDefaults.standard.set(Array(expandedPaths), forKey: "sidebar.expandedPaths")
    }

    init() {
        let settings = AppSettings.shared
        self.showsSidebar = settings.showSidebarOnLaunch
        self.showsEditor = settings.showEditorOnLaunch
        self.showsPreview = settings.showPreviewOnLaunch
        self.sidebarWidth = 260
    }

    init(
        showsSidebar: Bool,
        showsEditor: Bool,
        showsPreview: Bool,
        sidebarWidth: CGFloat = 260
    ) {
        self.showsSidebar = showsSidebar
        self.showsEditor = showsEditor
        self.showsPreview = showsPreview
        self.sidebarWidth = sidebarWidth
    }

    var hasVisibleWorkspacePane: Bool {
        showsEditor || showsPreview
    }

    var showsSidebarInLayout: Bool {
        showsSidebar && !isFocusMode
    }

    var clampedSidebarWidth: CGFloat {
        min(max(sidebarWidth, 200), 320)
    }

    func toggleSidebar() {
        showsSidebar.toggle()
    }

    func toggleEditor() {
        showsEditor.toggle()
    }

    func togglePreview() {
        showsPreview.toggle()
    }

    func toggleFocusMode() {
        isFocusMode.toggle()
    }

    func setSidebarWidth(_ width: CGFloat) {
        sidebarWidth = min(max(width, 200), 320)
    }
}
