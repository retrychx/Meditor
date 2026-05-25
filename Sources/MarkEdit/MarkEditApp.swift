import SwiftUI

@main
struct MarkEditApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .frame(minWidth: 900, minHeight: 500)
                .onAppear {
                    NSWindow.allowsAutomaticWindowTabbing = false
                }
                .onDisappear {
                    // Save all modified tabs on quit
                    for tab in appState.openTabs where tab.isModified {
                        appState.saveTab(tab)
                    }
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Folder…") {
                    openFolder()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])

                Button("Open File…") {
                    openFile()
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    appState.saveCurrentTab()
                }
                .keyboardShortcut("s", modifiers: .command)
            }
        }
    }

    private func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a project folder"

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
