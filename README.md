<p align="center">
  <img src="assets/icon.png" width="128" alt="MEditor Icon" />
</p>

<h1 align="center">MEditor</h1>

<p align="center">
  <strong>An agent-native document workstation for people who write technical docs</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14.0+-blue?logo=apple" alt="macOS 14+" />
  <img src="https://img.shields.io/badge/Swift-5.9-orange?logo=swift" alt="Swift 5.9" />
  <img src="https://img.shields.io/badge/license-MIT-green" alt="MIT License" />
  <img src="https://img.shields.io/badge/build-passing-brightgreen" alt="Build Passing" />
</p>

<p align="center">
  🌐 <a href="README.zh.md"><strong>中文</strong></a> | <strong>English</strong> | <a href="https://meditorapp.pages.dev"><strong>Website</strong></a>
</p>

---

MEditor is an **agent-native document workstation for people who write technical docs** on macOS. The core loop: **the Agent edits your document → the preview renders it instantly → you iterate together**.

Point it at a code repo or workspace and let the Agent do the writing engineers actually need — weekly reports, design proposals, changelogs, API references, meeting notes.

Pure SwiftUI + AppKit — **no Electron**. Bring-your-own-key — **your documents and your model credentials never leave your machine**.

---

## ✨ Features

### 🤖 A real Agent, not a chat box

- **14 tools, multi-turn loop** — The Agent reads, writes, patches, and searches documents; operates workspace files; drives the editor; and runs sandboxed shell commands — reasoning across tool calls until the job is done
- **Three backends** — OpenAI-compatible (8 built-in presets: OpenAI, DeepSeek, Kimi, GLM, Qwen, OpenRouter, Groq, Ollama), Anthropic, and a local Claude CLI backend that reuses your Claude Code login
- **BYOK** — Any OpenAI-compatible endpoint works; keys stay in your local settings
- **Streaming everywhere** — Responses stream token-by-token; tool steps render inline with expand/collapse detail

### 🛡 Built to be trusted with your files

- **Write confirmation** — The Agent asks before writing files; "allow all for this run" when you're in flow
- **Risk-tiered command sandbox** — Shell commands are classified by risk before execution
- **Context budget** — Token budget with automatic eviction keeps long sessions on track; stall detection stops runaway loops; read-only tools run in parallel
- **Observable runs** — Token usage and elapsed time shown per run
- **Inline diff review** — Agent edits land as reviewable diffs that never clobber your own typing; `@mention` pulls files into context; multi-session history keeps every conversation

### ⚡ AI woven into the writing flow

- **Slash commands** — Type `/` in the editor to pull up `/ask` `/polish` `/outline` `/translate` `/summary` `/fix` `/table` and more; commands that rewrite your document stream their changes as a diff you confirm before anything lands
- **Selection action bar** — Select text and a floating bar offers rewrite / tighten / expand / translate (select a list and it can become a table); Esc dismisses
- **Context automation** — Conversations auto-attach the current document (removable chip in the composer, can be disabled in Settings); when over budget it's smartly trimmed to the cursor's neighborhood plus head and tail
- **Diagnostics → one-click fix** — The diagnostics panel and pre-export checks offer "Let Agent fix it"; the model repairs, then re-scans so you can compare

### 🔄 The loop: edit → render → iterate

- **Live preview** — Real-time Markdown rendering (marked.js), code highlighting (highlight.js), diagrams (Mermaid.js)
- **Editor that keeps up** — Native `NSTextView` editing with 40+ language highlighting, bidirectional scroll sync, find & replace, Quick Open (⌘P), tabs, and an FSEvents-driven file browser
- **Images land on disk by themselves** — ⌘V a screenshot or drag an image in; it's saved to `assets/` and inserted as a relative path
- **Local history snapshots** — Every save keeps a snapshot with tiered retention; File History (⌃⌘H) diffs any two versions and restores in one click — and the restore itself is undoable
- **Global search (⌘⇧F)**, TOC outline, tab context menus (close others / reveal in Finder / save as template), and Quick Look previews from Finder

### 🚀 Deliver & share

- **LAN share** — Built-in HTTP server with one-time token auth; one-click **Gist** publishing too
- **Online publish** — One-click publish via Cloudflare
- **iOS companion** — Edit, chat, and publish over iCloud from your phone
- **Presentation & focus modes**, HTML / PDF / 2× PNG export, preview themes (GitHub / Nord / Dracula)
- **Pre-flight export checks** — PDF/HTML export first diagnoses dead links, missing images, and heading problems (can be turned off in Settings)
- **PDF export themes** — Paper size, margins, header/footer, and an optional cover page; the default export keeps links clickable
- **Copy as rich text** — ⌥⌘C copies rendered formatting, ready to paste into Feishu or email
- **Auto-update** via Sparkle — grab builds from [meditorapp.pages.dev](https://meditorapp.pages.dev)

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
bash scripts/bundle.sh          # builds both arches and creates a Universal .app
open .build/debug/MEditor.app
```

The bundle script compiles `arm64` + `x86_64` and `lipo`s them into a single
Universal binary, so the app runs natively on both Apple Silicon and Intel Macs.

> The `.app` is ad-hoc signed automatically. After first launch, associate `.md`/`.html` files via **Get Info → Open With → MEditor → Change All**.

### Versioning

The app version has a single source of truth per platform — **this is where you change it**:

- **macOS**: edit [`VERSION`](VERSION) at the repo root. `scripts/bundle.sh` injects it into `MEditor.app`'s `Info.plist` at packaging time (the version keys in `Sources/MEditor/Info.plist` are placeholders).
- **iOS**: edit `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in `Mobile/MEditorMobile.xcodeproj` (target build settings). `Mobile/MEditorMobile/Info.plist` references them as `$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)`.

Run `make version` to see the current version and these pointers.

### Open in Xcode

```bash
open Package.swift
```

---

## ⚙️ AI Setup

Open **Settings (⌘,) → AI** and pick a backend:

| Backend | What you need |
|---------|---------------|
| OpenAI-compatible preset | Pick one of the 8 presets (OpenAI, DeepSeek, Kimi, GLM, Qwen, OpenRouter, Groq, Ollama), paste your API key, pick a model |
| Anthropic | API key + model (e.g. `claude-opus-4-5`) |
| Claude CLI | Nothing — reuses your local Claude Code login |
| Custom endpoint | Any OpenAI-compatible Base URL + key + model |

No key? The Claude CLI backend gets you running with zero configuration.

---

## 🏗 Project Structure

```
MEditor/
├── Package.swift
├── scripts/
│   ├── bundle.sh          # .app assembler
│   └── test.sh            # Xcode-toolchain test runner
├── docs/                  # Design specs & historical analyses
├── plans/                 # Active development plans
└── Sources/MEditor/
    ├── Models/            # EditorTab, FileItem, AgentTool, PluginSkill…
    ├── Protocols/         # FileService, SyntaxHighlight, AgentContext…
    ├── Services/
    │   ├── AI/
    │   │   ├── Agent/
    │   │   │   ├── AgentRunner.swift          # Multi-turn loop & state
    │   │   │   ├── CommandSandbox.swift       # Risk-tiered shell sandbox
    │   │   │   ├── AgentHistoryBudget.swift   # Context token budget
    │   │   │   ├── Backends/
    │   │   │   │   ├── AgentBackend.swift     # Protocol + default streaming fallback
    │   │   │   │   ├── RestAgentBackend.swift # OpenAI & Anthropic SSE
    │   │   │   │   └── ClaudeCLIBackend.swift # claude CLI subprocess
    │   │   │   └── Tools/                     # Document, editor, workspace, shell tools
    │   │   ├── InlineEditAgent.swift          # Selection-scoped edits with diff review
    │   │   ├── AIService.swift                # Chat completions & provider presets
    │   │   └── BeautifyAgent.swift            # Single-shot document polish
    │   ├── Core/          # AppSettings, Localization, MarkdownFormatter
    │   ├── File/          # FileService, FileWatcher, FileType config
    │   └── Calendar/      # CalendarService (EventKit)
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

**Delivered**
- [x] Real Agent: 14 tools, multi-turn loop, three backends (OpenAI-compatible / Anthropic / Claude CLI), BYOK
- [x] Agent hardening: write confirmation, risk-tiered sandbox, context budget, stall detection, parallel read-only tools, usage display
- [x] Inline edit diff review, `@mention` context, multi-session history
- [x] Slash command library, selection action bar, auto-attached document context
- [x] Image paste/drag auto-save, local history snapshots, tab context menu
- [x] Pre-export diagnostics with one-click Agent fix, PDF export themes, copy as rich text
- [x] Global search (⌘⇧F), Quick Look plugin
- [x] LAN share + Cloudflare online publish
- [x] iOS companion (iCloud edit / chat / publish)
- [x] Presentation & focus modes, HTML export, preview themes, Sparkle auto-update

**Next** (Phase 1–3)
- [ ] Onboarding — first-launch guide, zero-config Claude CLI default, scripted demo
- [ ] One-click rollback of an Agent run (run-level checkpoints)

**Later** (Phase 4–6)
- [ ] Spotlight indexing & Shortcuts intents
- [ ] MCP server — expose the Agent's tools to Claude Desktop / Cursor

---

## 🤝 Contributing

PRs welcome. Please run `make test` before opening one.

---

## 📄 License

[MIT](LICENSE)

---

*Built with Swift and SwiftUI on macOS*
