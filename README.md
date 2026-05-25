# MarkEdit

A native macOS Markdown editor built with SwiftUI.

## Features

- **Live Preview** — Real-time Markdown rendering powered by [`swift-markdown-ui`](https://github.com/gonzalezreal/swift-markdown-ui)
- **Syntax Highlighting** — Code blocks highlighted via [Splash](https://github.com/JohnSundell/Splash)
- **Sidebar** — File browser for project navigation
- **WYSIWYG-like Editing** — Web-based editor with native integration
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
Sources/MarkEdit/
├── MarkEditApp.swift          # App entry point
├── Models/
│   ├── EditorTab.swift        # Editor tab management
│   └── FileItem.swift         # File representation
├── Resources/
│   ├── Editor/editor.html     # Web-based editor
│   └── Preview/markdown.html  # Preview rendering
├── Services/
│   └── FileService.swift      # File I/O operations
├── ViewModels/
│   └── AppState.swift         # Global app state
└── Views/
    ├── ContentView.swift      # Root view
    ├── Editor/
    │   ├── EditorView.swift
    │   └── NativeEditorView.swift
    ├── Preview/
    │   ├── PreviewPanel.swift
    │   ├── SplashHighlighter.swift
    │   └── WebPreviewView.swift
    └── Sidebar/
        └── FileSidebar.swift
```

## License

MIT
