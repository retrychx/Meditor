import Observation
import SwiftUI

enum ActiveMainView {
    case document, todos, calendar
}

@MainActor
@Observable
final class WorkspaceUIState {
    private let settings: AppSettings

    var showsSidebar: Bool {
        didSet { settings.showSidebarOnLaunch = showsSidebar }
    }

    var showsEditor: Bool {
        didSet { settings.showEditorOnLaunch = showsEditor }
    }

    var showsPreview: Bool {
        didSet { settings.showPreviewOnLaunch = showsPreview }
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

    init(settings: AppSettings = .shared) {
        self.settings = settings
        self.showsSidebar = settings.showSidebarOnLaunch
        self.showsEditor = settings.showEditorOnLaunch
        self.showsPreview = settings.showPreviewOnLaunch
        self.sidebarWidth = 260
    }

    init(
        showsSidebar: Bool,
        showsEditor: Bool,
        showsPreview: Bool,
        sidebarWidth: CGFloat = 260,
        settings: AppSettings = .shared
    ) {
        self.settings = settings
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
