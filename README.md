<p align="center">
  <img src="assets/icon.png" width="128" alt="MEditor Icon" />
</p>

<h1 align="center">MEditor</h1>

<p align="center">
  <strong>A native macOS Markdown editor with a built-in AI Agent</strong>
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

MEditor is a **pure SwiftUI + AppKit** Markdown editor for macOS. It ships with a built-in AI Agent that can read, write, and refactor your documents using tool calls — no plugins, no Electron, no cloud sync required.

---

## ✨ Features

### 🤖 AI Agent (the main thing)

- **Multi-turn tool loop** — The Agent reasons, calls tools, reads results, and keeps going until the task is done
- **Document tools** — Read, write, patch, and insert into the current document via precise tool calls
- **Workspace tools** — List files, search across the workspace, open tabs, run shell commands (sandboxed)
- **Streaming output** — Responses appear word-by-word; tool steps show inline with expand/collapse detail
- **OpenAI & Anthropic** — Full SSE streaming for both wire protocols; ClaudeCLI backend also supported
- **Bring your own key** — Works with any OpenAI-compatible endpoint (Ollama, OpenRouter, local LLMs)
- **Skill system** — Built-in skills (summarize, beautify, review…) plus a curated gallery to extend

### 📝 Editing & Preview

- **Live Preview** — Real-time Markdown rendering (marked.js), code highlighting (highlight.js), diagrams (Mermaid.js)
- **Syntax Highlighting** — 40+ languages in both editor and preview
- **Bidirectional Scroll Sync** — Editor and preview scroll in sync, with anti-loop protection
- **Find & Replace** — Native find panel with Jump to Line and Replace
- **HTML Preview** — `.html`/`.htm` files render as web pages

### 📂 Files & Tabs

- **File Browser** — Sidebar with search, context menus, FSEvents auto-refresh
- **Tab Management** — Drag-to-reorder, close confirmation, reopen closed tab (⌘⇧T)
- **Quick Open** — Fuzzy file finder (⌘P)

### 🗂 Workspace

- **Preview Themes** — GitHub (light), Nord, Dracula (dark)
- **Export** — HTML / PDF / 2× PNG; HTML → Markdown conversion
- **LAN Sharing** — Built-in HTTP server with one-time token auth
- **Session Restore** — Remembers tabs, folder, and selection across launches
- **Auto-Save** — Optional timed auto-save; saves on quit
- **No Electron** — Pure Swift, bundled JS runs fully offline

---

## 📸 Screenshots

> *Coming soon — contributions welcome!*

---

## 📋 Requirements

- **macOS** 14.0+ (Sonoma)
- **Xcode** 15.0+ (for development)
- **Swift** 5.9+

## 🔧 Build & Run

### Quick start

```bash
git clone https://github.com/retrychx/Meditor.git
cd Meditor
swift build
swift run
```

### Run tests

```bash
./scripts/test.sh   # uses full Xcode toolchain
make test           # short alias
```

### Create a .app bundle

```bash
swift build
bash scripts/bundle.sh
open .build/debug/MEditor.app
```

> The `.app` is ad-hoc signed automatically. After first launch, associate `.md`/`.html` files via **Get Info → Open With → MEditor → Change All**.

### Open in Xcode

```bash
open Package.swift
```

---

## ⚙️ AI Setup

Open **Settings (⌘,) → AI** and fill in:

| Field | Example |
|-------|---------|
| Provider | OpenAI / Anthropic / OpenAI-compatible |
| Base URL | `https://api.openai.com/v1` |
| API Key | `sk-...` |
| Model | `gpt-4o` / `claude-opus-4-5` |

Any OpenAI-compatible endpoint works (Ollama, LM Studio, OpenRouter, etc.).

---

## 🏗 Project Structure

```
MEditor/
├── Package.swift
├── scripts/
│   ├── bundle.sh          # .app assembler
│   └── test.sh            # Xcode-toolchain test runner
├── docs/                  # Design specs & roadmap
└── Sources/MEditor/
    ├── Models/            # EditorTab, FileItem, AgentTool, PluginSkill…
    ├── Protocols/         # FileService, SyntaxHighlight, AgentContext…
    ├── Services/
    │   ├── AI/
    │   │   ├── Agent/
    │   │   │   ├── AgentRunner.swift          # Multi-turn loop & state
    │   │   │   ├── Backends/
    │   │   │   │   ├── AgentBackend.swift     # Protocol + default streaming fallback
    │   │   │   │   ├── RestAgentBackend.swift # OpenAI & Anthropic SSE
    │   │   │   │   └── ClaudeCLIBackend.swift # claude CLI subprocess
    │   │   │   └── Tools/                     # Document, editor, workspace tools
    │   │   ├── AIService.swift                # Chat (non-agent) completions
    │   │   └── BeautifyAgent.swift            # Single-shot document polish
    │   ├── Core/          # AppSettings, Localization, MarkdownFormatter
    │   ├── File/          # FileService, FileWatcher, FileType config
    │   └── Calendar/      # CalendarService protocol + InternalCalendar impl
    ├── Managers/          # Tab, FileTree, Share, Template, Todo…
    └── Views/
        ├── Agent/         # AgentStepView, AgentResultPanel
        ├── AI/            # AIAssistant, AtMention composer
        ├── Editor/        # NativeEditorView, TabBar, InlineEdit…
        ├── Preview/       # MarkdownWebPreview, TOC, ExportBar
        ├── Sidebar/       # FileSidebar, FileRow, TodoSidebar…
        └── Shared/        # DesignTokens, ChromeButton, Toast…
```

---

## 🗺 Roadmap

**Now**
- [x] AI Agent with streaming (OpenAI + Anthropic SSE)
- [x] Tool call expand/collapse with result details
- [x] Built-in skills & curated gallery
- [x] Session restore, auto-save, LAN share

**Next**
- [ ] Editor font & size settings
- [ ] Git status indicators in sidebar
- [ ] Global search (⌘⇧F)
- [ ] Onboarding for first-time AI setup

**Later**
- [ ] Multi-window support
- [ ] MCP (Model Context Protocol) tool servers
- [ ] iOS / iPadOS companion

---

## 🤝 Contributing

PRs welcome. Please run `make test` before opening one.

---

## 📄 License

[MIT](LICENSE)

---

*Built with Swift and SwiftUI on macOS*
