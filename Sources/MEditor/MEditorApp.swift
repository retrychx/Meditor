import SwiftUI

@main
struct MEditorApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .frame(minWidth: 900, minHeight: 500)
                .onAppear {
                    NSWindow.allowsAutomaticWindowTabbing = false
                    // Restore previous session (root folder + open tabs + selection).
                    // No-op on first launch or if every bookmark has gone stale.
                    appState.restoreSession()
                }
                .onOpenURL { url in
                    handleOpenURL(url)
                }
                .onDisappear {
                    // Save all modified tabs on quit
                    for tab in appState.openTabs where tab.isModified {
                        appState.saveTab(tab)
                    }
                    // Force-flush session to disk so the next launch restores it.
                    appState.flushSession()
                }
        }
        Settings {
            SettingsView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(L("menu.openFolder")) {
                    openFolder()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])

                Button(L("menu.openFile")) {
                    openFile()
                }
                .keyboardShortcut("o", modifiers: .command)

                Divider()

                Button(L("menu.newFile")) {
                    if let root = appState.rootURL {
                        var newURL = root.appendingPathComponent("untitled.md")
                        var counter = 1
                        while FileManager.default.fileExists(atPath: newURL.path) {
                            newURL = root.appendingPathComponent("untitled \(counter).md")
                            counter += 1
                        }
                        FileManager.default.createFile(atPath: newURL.path, contents: Data())
                        let item = FileItem(url: newURL, isDirectory: false)
                        appState.openFile(item)
                    }
                }
                .keyboardShortcut("n", modifiers: .command)
            }

            CommandGroup(replacing: .saveItem) {
                Button(L("menu.save")) {
                    appState.saveCurrentTab()
                }
                .keyboardShortcut("s", modifiers: .command)
            }

            CommandGroup(replacing: .textFormatting) {
                Button(L("menu.find")) {
                    let menuItem = NSMenuItem()
                    menuItem.tag = 1
                    NSApp.sendAction(#selector(NSTextView.performFindPanelAction(_:)), to: nil, from: menuItem)
                }
                .keyboardShortcut("f", modifiers: .command)

                Button(L("menu.findNext")) {
                    let menuItem = NSMenuItem()
                    menuItem.tag = 2
                    NSApp.sendAction(#selector(NSTextView.performFindPanelAction(_:)), to: nil, from: menuItem)
                }
                .keyboardShortcut("g", modifiers: .command)

                Button(L("menu.findPrevious")) {
                    let menuItem = NSMenuItem()
                    menuItem.tag = 3
                    NSApp.sendAction(#selector(NSTextView.performFindPanelAction(_:)), to: nil, from: menuItem)
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])

                Divider()

                Button(L("menu.useSelectionForFind")) {
                    let menuItem = NSMenuItem()
                    menuItem.tag = 7
                    NSApp.sendAction(#selector(NSTextView.performFindPanelAction(_:)), to: nil, from: menuItem)
                }
                .keyboardShortcut("e", modifiers: .command)

                Button(L("menu.jumpToLine")) {
                    let menuItem = NSMenuItem()
                    menuItem.tag = 12
                    NSApp.sendAction(#selector(NSTextView.performFindPanelAction(_:)), to: nil, from: menuItem)
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])

                Divider()

                Button(L("menu.replace")) {
                    let menuItem = NSMenuItem()
                    menuItem.tag = 1
                    NSApp.sendAction(#selector(NSTextView.performFindPanelAction(_:)), to: nil, from: menuItem)
                }
                .keyboardShortcut("f", modifiers: [.command, .option])
            }

            CommandGroup(replacing: .windowList) {
                Button(L("menu.closeTab")) {
                    if let id = appState.selectedTabID {
                        appState.closeTab(id)
                    }
                }
                .keyboardShortcut("w", modifiers: .command)

                Button(L("menu.reopenClosedTab")) {
                    appState.reopenLastClosedTab()
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])

                Button(L("menu.nextTab")) {
                    appState.selectNextTab()
                }
                .keyboardShortcut("]", modifiers: [.command, .shift])

                Button(L("menu.previousTab")) {
                    appState.selectPreviousTab()
                }
                .keyboardShortcut("[", modifiers: [.command, .shift])

                Divider()

                Button(L("menu.quickOpen")) {
                    appState.showingQuickOpen = true
                }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(appState.rootURL == nil)
            }
        }
    }

    private func handleOpenURL(_ url: URL) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return }
        if isDir.boolValue {
            appState.openFolder(url)
        } else {
            // Ensure the parent folder is opened so the sidebar has context.
            if appState.rootURL == nil {
                let parent = url.deletingLastPathComponent()
                appState.openFolder(parent)
            }
            let item = FileItem(url: url, isDirectory: false)
            appState.openFile(item)
        }
    }

    private func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = L("panel.chooseFolder")

        if panel.runModal() == .OK, let url = panel.url {
            appState.openFolder(url)
        }
    }

    private func openFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.init(filenameExtension: "md")!, .init(filenameExtension: "html")!, .init(filenameExtension: "htm")!].compactMap { $0 }

        if panel.runModal() == .OK, let url = panel.url {
            let item = FileItem(url: url, isDirectory: false)
            appState.openFile(item)
        }
    }
}
