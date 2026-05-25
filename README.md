# MEditor

A native macOS Markdown editor built with SwiftUI.

## Features

- **Live Preview** — Real-time Markdown rendering with highlight.js + marked.js + Mermaid
- **Syntax Highlighting** — Code blocks highlighted via highlight.js (supports 40+ languages)
- **Sidebar** — File browser with search for project navigation
- **Bidirectional Scroll Sync** — Editor and preview scroll in sync
- **File Tree Auto-Refresh** — FSEvents-based file watcher
- **Tab Management** — Drag-to-reorder tabs with save confirmation
- **Drag-to-Resize Panels** — Resizable sidebar, editor, and preview panels
- **macOS Native** — Built with SwiftUI, designed for macOS 14+

## Requirements

- macOS 14.0+ (Sonoma)
- Xcode 15.0+
- Swift 5.9+

## Build & Run

```bash
swift build
swift run
```

Or open in Xcode:

```bash
open Package.swift
```

## Project Structure

```
Sources/MEditor/
├── MEditorApp.swift           # App entry point
├── Models/
│   ├── EditorTab.swift        # Editor tab management
│   └── FileItem.swift         # File representation
├── Protocols/
│   ├── FileServiceProtocol.swift
│   └── SyntaxHighlightEngine.swift
├── Resources/
│   └── Preview/               # JS libraries (marked, highlight, mermaid)
├── Services/
│   ├── FileService.swift      # File I/O operations
│   ├── FileWatcherService.swift # FSEvents file tree watcher
│   ├── FileTypeConfiguration.swift
│   ├── HTMLHighlightEngine.swift
│   ├── HighlightService.swift
│   └── MarkdownHighlightEngine.swift
├── ViewModels/
│   └── AppState.swift         # Global app state
└── Views/
    ├── ContentView.swift      # Root view
    ├── Editor/
    │   ├── EditorTabBar.swift
    │   ├── EditorView.swift
    │   └── NativeEditorView.swift
    ├── Preview/
    │   ├── MarkdownWebPreview.swift
    │   ├── PreviewPanel.swift
    │   └── WebPreviewView.swift
    ├── Shared/
    │   ├── PanelLabel.swift
    │   └── VisualEffect.swift
    └── Sidebar/
        ├── FileRow.swift
        └── FileSidebar.swift
```

## License

MIT
