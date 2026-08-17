# MEditor — Code Quality Review & Feature Roadmap

> ⚠️ **Outdated (annotated 2026-08-18)**: This is a snapshot review of the initial release (2026-05-26, pre-Agent). The §2 Feature Roadmap and the code metrics (23 files / ~1,350 lines, "no unit tests") no longer reflect the project — MEditor is now an agent-native document workstation with a 14-tool Agent and a full test suite. Current positioning and sequencing: [`plans/2026-08-18-agent-workstation-plan.md`](../plans/2026-08-18-agent-workstation-plan.md). Several issues listed here (no tests, no preferences window, no session restore) have since been fixed.

> Review date: 2026-05-26
> Project version: Initial release (post MarkEdit → MEditor rename)

---

## Project Overview

| Metric | Value |
|--------|-------|
| Swift source files | 23 files, ~1,350 lines of code |
| HTML/CSS/JS resources | 4 files (~2,700 lines, including embedded styles and JS libs) |
| Architecture layers | Models / Protocols / Services / ViewModels / Views |
| Build status | ✅ Zero errors, zero warnings |
| macOS target | 14.0+ (Sonoma) |
| SPM dependencies | swift-markdown-ui, Splash (unused) |

---

## 1. Code Quality Analysis

### ✅ Strengths

**1. Clean Architecture**
- Protocol-oriented design — `FileServiceProtocol` / `SyntaxHighlightEngine` for testability and extensibility
- Service registry pattern — `HighlightService.shared.register()` makes it easy to add new language engines
- `@Observable` macro replaces Combine, keeping state management concise

**2. Performance Boundaries**
- Large files (>500KB) skip regex highlighting to prevent UI freezes
- Content update debounce (50ms) + highlight debounce (300ms) for smooth typing
- Mermaid XSS protection via JSON encoder instead of string concatenation
- Anti-loop protection in bidirectional scroll sync (`isProgrammaticScroll` flag, 100ms reset)

**3. macOS Native Feel**
- Uses native components: `NSVisualEffectView`, `NSTextView`, `WKWebView`
- Full dark/light mode support
- Drag dividers with 6px hit target vs 1px visual line — attention to UX detail

**4. Well-Organized Code**
- Directory structure maps clearly to responsibilities
- Consistent naming conventions, clear SwiftUI/AppKit boundary

---

### ⚠️ Issues to Address

#### Medium Priority

| # | Issue | File | Description |
|---|-------|------|-------------|
| 1 | **HTML/CSS/JS embedded in Swift strings** | `MarkdownWebPreview.swift` | ~300 lines of CSS+JS+HTML in `"""` string literals. Should be extracted to standalone `.html` template files with runtime placeholder substitution |
| 2 | **Resource copy code duplication** | `MarkdownWebPreview.swift:386-413` | `prepareResources()` replicates the same logic 3 times for each JS file. Refactor into a loop or `copyIfNeeded` helper |
| 3 | **FileSidebar List duplication** | `FileSidebar.swift:61-96` | Search mode and non-search mode List views are nearly identical — only the data source differs. Can be merged |
| 4 | **Stale bundle ID** | `FileWatcherService.swift:16` | GCD queue label still reads `com.markedit.filewatcher`, should be `com.meditor.filewatcher` |
| 5 | **Hardcoded cache path** | `MarkdownWebPreview.swift:375` | `com.markedit.preview` — same stale bundle ID issue |

#### Low Priority

| # | Issue | File | Description |
|---|-------|------|-------------|
| 6 | **Silent `try?` failures** | `MarkdownWebPreview.swift:383-411` | JS file copy failures produce no feedback — preview goes blank with no error shown |
| 7 | **`openFolder()` duplication** | `MEditorApp.swift` + `ContentView.swift` | Nearly identical `NSOpenPanel` logic in two places, could be extracted |
| 8 | **WKWebView lingering** | `WebPreviewView.swift` | Missing `dismantleNSView` implementation, WebView memory not immediately reclaimed |
| 9 | **Hardcoded highlight theme** | `MarkdownWebPreview.swift:89-120` | GitHub theme CSS embedded in Swift, no user theme selection |
| 10 | **Hardcoded 14pt editor font** | `NativeEditorView.swift:29,177` | Font size and family not user-configurable |
| 11 | **No unit tests** | — | Zero test files across the entire project |

---

## 2. Feature Roadmap

### P1 — Core (Recommended First)

| Feature | Description | Effort |
|---------|-------------|--------|
| **App icon** | Currently blank default icon; needs `.icns` | ~1h ✅ Done |
| **Document type association** | Register `.md` files in `Info.plist` so double-click opens MEditor | ~1h ✅ Done |
| **Editor font/size settings** | Preferences panel for font family, size, line height | ~3h |
| **Preferences window** | Use `Settings` Scene (`SettingsLink`) for fonts, themes, auto-save | ~2h |
| **Auto-save + session restore** | Remember open files and unsaved content across launches | ~4h |
| **Extract HTML template** | Move inline HTML/CSS/JS out of Swift into standalone template files | ~2h |

### P2 — Experience Enhancement

| Feature | Description | Effort |
|---------|-------------|--------|
| **Git status indicators** | Show `M`/`A`/`?` badges next to files in sidebar | ~5h |
| **Global search** | `⌘⇧F` to recursively search file contents with match preview | ~6h |
| **Outline / TOC panel** | Parse `##` headings into a clickable table of contents sidebar | ~4h |
| **Image paste/drop** | Paste images from clipboard → auto-save to `assets/` → insert `![](...)` | ~3h |
| **Code folding** | NSTextView-native code folding with gutter markers | ~5h |
| **Export to PDF/HTML** | Export rendered Markdown as PDF or standalone HTML | ~2h |

### P3 — Polish

| Feature | Description | Effort |
|---------|-------------|--------|
| **Multi-window** | Independent per-window state via `WindowGroup` + `openWindow` | ~6h |
| **Vim mode** | Vim keybinding emulation in the editor | Large |
| **CSV/JSON/Log preview** | Formatted preview for non-Markdown files | ~4h |
| **Typewriter mode** | Current line stays centered (iA Writer style) | ~3h |
| **Word/character count** | Optional word/char/line count in status bar | ~1h |
| **Minimap** | Right-side thumbnail navigation | Large |
| **Theme marketplace** | Downloadable editor highlight themes | Large |

---

## 3. Overall Assessment

**7 / 10**

As a first release, the architecture choices are solid (SwiftUI + Observation + WKWebView), key performance boundaries are considered, and it covers the core Markdown editor feature set.

**Recommended next steps:**
1. Extract HTML templates from Swift strings (makes style changes 10× easier)
2. Add preferences window
3. Implement session restore and auto-save
