<p align="center">
  <img src="assets/icon.png" width="128" alt="MEditor Icon" />
</p>

<h1 align="center">MEditor</h1>

<p align="center">
  <strong>A native macOS Markdown & HTML editor built with SwiftUI</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14.0+-blue?logo=apple" alt="macOS 14+" />
  <img src="https://img.shields.io/badge/Swift-5.9-orange?logo=swift" alt="Swift 5.9" />
  <img src="https://img.shields.io/badge/license-MIT-green" alt="MIT License" />
  <img src="https://img.shields.io/badge/build-passing-brightgreen" alt="Build Passing" />
</p>

<p align="center">
  🌐 <a href="README.zh.md"><strong>中文</strong></a> | <strong>English</strong>
</p>

---

## ✨ Features

### Editing & Preview
- **📝 Live Preview** — Real-time Markdown rendering with marked.js, code highlighting via highlight.js, and diagram support via Mermaid.js
- **🎨 Syntax Highlighting** — 40+ languages supported in the editor (native `NSTextView`) and preview (highlight.js with full alias mapping)
- **🔀 Bidirectional Scroll Sync** — Scrolling in the editor syncs the preview and vice versa, with anti-loop protection
- **🔍 Find & Replace** — Native find panel: Find, Find Next/Previous, Use Selection for Find, Jump to Line, Replace
- **🖥 HTML Preview** — `.html`/`.htm` files render directly as web pages

### Files & Tabs
- **📂 File Browser** — Sidebar with search, context menus (new file/folder, rename, delete, reveal in Finder), persisted expansion state
- **📁 File Tree Auto-Refresh** — FSEvents-based file watcher that detects external changes instantly
- **📑 Tab Management** — Drag-to-reorder tabs, close confirmation (save/discard/cancel), reopen closed tab (⌘⇧T), next/previous tab
- **⚡️ Quick Open** — Fuzzy file finder (⌘P) with keyboard navigation

### Workspace
- **🎨 Preview Themes** — GitHub (light), Nord, Dracula (dark); the whole window chrome adapts and the choice is persisted
- **📤 Export** — Export the preview to HTML / PDF / Image (2× PNG); HTML files can also export to Markdown
- **🌐 LAN Sharing** — Built-in HTTP server (NWListener) shares open documents over the local network; access is gated by a one-time token and an allowlist limited to currently open files
- **💾 Session Restore** — Remembers the root folder, open tabs (order), and selection across launches via security-scoped bookmarks
- **⏱ Auto-Save** — Optional timed auto-save (configurable interval); modified tabs are also saved on quit
- **⚙️ Settings** — Preview font size, auto-save, default launch layout, LAN share port (⌘,)
- **🔄 Drag-to-Resize Panels** — Toggle and resize sidebar, editor, and preview panels independently
- **📊 Status Bar** — Cursor position (Ln/Col), file size, UTF-8 indicator
- **💻 macOS Native** — Pure SwiftUI + AppKit, no Electron, no web wrappers; bundled JS libraries work fully offline

## 📸 Screenshots

> *Coming soon*

---

## 📋 Requirements

- **macOS** 14.0+ (Sonoma)
- **Xcode** 15.0+ (for development)
- **Swift** 5.9+

## 🔧 Build & Run

### Quick start

```bash
# Clone the repository
git clone https://github.com/retrychx/Meditor.git
cd Meditor

# Build with Swift Package Manager
swift build

# Run directly (lightweight, no .app bundle)
swift run
```

### Run tests

```bash
# Uses the full Xcode toolchain automatically
./scripts/test.sh

# Short alias
make test
```

### Create a proper .app bundle

```bash
# Build then bundle into a .app
swift build
bash scripts/bundle.sh

# Launch with icon, Dock presence, and document associations
open .build/debug/MEditor.app
```

> **Note:** The `.app` bundle is automatically ad-hoc signed by `bundle.sh`. After opening it once, you can associate `.md` and `.html` files with MEditor via **Get Info → Open with → MEditor → Change All**.

### Open in Xcode

```bash
open Package.swift
```

---

## 🏗 Project Structure

```
MEditor/
├── Package.swift                # Swift Package Manager manifest
├── scripts/
│   └── bundle.sh                # .app bundle assembler
├── docs/
│   └── code-review-and-roadmap.md  # Code quality analysis & feature plan
└── Sources/MEditor/
    ├── MEditorApp.swift         # App entry point & @main struct
    ├── Info.plist               # Bundle config & document type associations
    ├── Models/
    │   ├── EditorTab.swift      # Tab model (url, content, language, modified flag)
    │   └── FileItem.swift       # File tree node (url, directory, children)
    ├── Protocols/
    │   ├── FileServiceProtocol.swift      # Abstract file I/O
    │   └── SyntaxHighlightEngine.swift    # Abstract syntax highlighting
    ├── Resources/
    │   ├── AppIcon.icns         # Application icon (all resolutions)
    │   └── Preview/             # Bundled JS libraries (no network required)
    │       ├── marked.min.js    # Markdown → HTML renderer
    │       ├── highlight.min.js # Code syntax highlighter
    │       └── mermaid.min.js   # Diagram renderer (flowcharts, sequence, etc.)
    ├── Services/
    │   ├── FileService.swift              # File I/O implementation
    │   ├── FileWatcherService.swift       # FSEvents directory watcher
    │   ├── FileTypeConfiguration.swift    # File type registry (icon, color, language)
    │   ├── HTMLHighlightEngine.swift      # Regex-based HTML highlighter
    │   ├── HighlightService.swift         # Syntax engine registry
    │   └── MarkdownHighlightEngine.swift  # Regex-based Markdown highlighter
    ├── ViewModels/
    │   └── AppState.swift       # Global observable state (@Observable macro)
    └── Views/
        ├── ContentView.swift    # Root layout (welcome screen + main layout)
        ├── Editor/
        │   ├── EditorTabBar.swift       # Drag-to-reorder tab bar
        │   ├── EditorView.swift         # Editor container
        │   └── NativeEditorView.swift   # NSTextView wrapper with highlighting
        ├── Preview/
        │   ├── MarkdownWebPreview.swift # WKWebView for Markdown rendering
        │   ├── PreviewPanel.swift       # Preview container
        │   └── WebPreviewView.swift     # WKWebView for raw HTML
        ├── Shared/
        │   ├── PanelLabel.swift         # Reusable panel header
        │   └── VisualEffect.swift       # NSVisualEffectView wrapper
        └── Sidebar/
            ├── FileRow.swift            # File item row with context menu
            └── FileSidebar.swift        # File tree with search & CRUD
```

---

## 🔍 Code Quality & Roadmap

See [`docs/code-review-and-roadmap.md`](docs/code-review-and-roadmap.md) for a detailed code quality assessment and future feature roadmap.

Highlights from the review:

| Area | Rating |
|------|--------|
| **Architecture** | ⭐ Protocol-oriented with clean Service layer |
| **Performance** | ⭐ Large file threshold (500KB), debounced updates |
| **Security** | ⭐ Per-session token + allowlist for LAN share, standardized-path traversal guard, JSON encoding for preview |
| **Needs Work** | 🔧 HTML templates embedded in Swift strings |
| **Needs Work** | 🔧 Resource copy logic duplication |
| **Shipped** | ✅ Preferences window, session restore, export (PDF/HTML/image), LAN share, themes |
| **Next Up** | Editor font settings, Git status indicators, global search (⌘⇧F) |

---

## 📄 License

[MIT](LICENSE)

---

*Built with ❤️ using Swift and AppKit*
