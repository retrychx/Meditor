import Observation
import SwiftUI

@MainActor
@Observable
final class WorkspaceUIState {
    enum RightPanelKind: String, CaseIterable, Identifiable {
        case insert
        case pageInfo
        case comments
        case share
        case search

        var id: String { rawValue }
    }

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
    var rightPanel: RightPanelKind?

    init() {
        let settings = AppSettings.shared
        self.showsSidebar = settings.showSidebarOnLaunch
        self.showsEditor = settings.showEditorOnLaunch
        self.showsPreview = settings.showPreviewOnLaunch
        self.sidebarWidth = 260
        self.rightPanel = nil
    }

    init(
        showsSidebar: Bool,
        showsEditor: Bool,
        showsPreview: Bool,
        sidebarWidth: CGFloat = 260,
        rightPanel: RightPanelKind? = nil
    ) {
        self.showsSidebar = showsSidebar
        self.showsEditor = showsEditor
        self.showsPreview = showsPreview
        self.sidebarWidth = sidebarWidth
        self.rightPanel = rightPanel
    }

    var hasVisibleWorkspacePane: Bool {
        showsEditor || showsPreview
    }

    var showsSidebarInLayout: Bool {
        showsSidebar && !isFocusMode
    }

    var showsRightPanelInLayout: Bool {
        rightPanel != nil && !isFocusMode
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

    func toggleRightPanel(_ panel: RightPanelKind) {
        rightPanel = rightPanel == panel ? nil : panel
    }

    func closeRightPanel() {
        rightPanel = nil
    }

    func toggleFocusMode() {
        isFocusMode.toggle()
    }

    func setSidebarWidth(_ width: CGFloat) {
        sidebarWidth = min(max(width, 200), 320)
    }
}
