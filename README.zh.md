<p align="center">
  <img src="assets/icon.png" width="128" alt="MEditor 图标" />
</p>

<h1 align="center">MEditor</h1>

<p align="center">
  <strong>macOS 上给技术人写文档的 Agent 工作台</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14.0+-blue?logo=apple" alt="macOS 14+" />
  <img src="https://img.shields.io/badge/Swift-5.9-orange?logo=swift" alt="Swift 5.9" />
  <img src="https://img.shields.io/badge/%E5%8D%8F%E8%AE%AE-MIT-green" alt="MIT License" />
  <img src="https://img.shields.io/badge/%E7%BC%96%E8%AF%91-%E9%80%9A%E8%BF%87-brightgreen" alt="编译通过" />
</p>

<p align="center">
  🌐 <strong>中文</strong> | <a href="README.md"><strong>English</strong></a> | <a href="https://meditorapp.pages.dev"><strong>官网</strong></a>
</p>

---

MEditor 是 **macOS 上给技术人写文档的 Agent 工作台**。核心闭环：**Agent 改文档 → 预览立即渲染 → 人机迭代**。

把它指向一个代码仓库或工作区，让 Agent 把工程师真正要写的文档写好 —— 周报、技术方案、changelog、API 文档、会议纪要。

纯 SwiftUI + AppKit，**无 Electron**；自带密钥（BYOK），**你的文档和模型密钥永远不离开你的机器**。

---

## ✨ 功能特性

### 🤖 真 Agent，不是聊天框

- **14 个工具，多轮循环** — Agent 读写、补丁式修改、搜索文档，操作工作区文件，驱动编辑器，执行沙盒 Shell 命令 —— 在多轮工具调用中持续推理，直到把活干完
- **三种后端** — OpenAI 兼容（内置 8 家预设：OpenAI、DeepSeek、Kimi、GLM、通义千问、OpenRouter、Groq、Ollama）、Anthropic，以及复用本机 Claude Code 登录态的 Claude CLI 后端
- **自带密钥（BYOK）** — 兼容任何 OpenAI 格式端点，密钥只存在本地设置里
- **全程流式** — 回复逐字流出；工具步骤内联展示，支持展开/折叠查看详情

### 🛡 敢让它动你的文件

- **写文件前确认** — Agent 写入前先问你；顺手时可"本次运行全部允许"
- **命令沙盒风险分级** — Shell 命令按风险分级后再执行
- **上下文预算** — token 预算自动淘汰，长会话不跑偏；停滞检测掐死空转循环；只读工具并行执行
- **运行可观测** — 每次运行展示 token 用量与耗时
- **行内 diff 审阅** — Agent 的修改以可审阅的 diff 落地，绝不覆盖你正在输入的内容；`@mention` 把文件拉进上下文；多会话历史保留每段对话

### 🔄 闭环：改 → 渲染 → 迭代

- **实时预览** — 基于 marked.js 的 Markdown 渲染、highlight.js 代码高亮、Mermaid.js 图表
- **跟得上的编辑器** — 原生 `NSTextView` 编辑，40+ 语言高亮，双向滚动同步，查找替换，快速打开（⌘P），标签页，FSEvents 驱动的文件浏览器

### 🚀 交付与分享

- **局域网分享** — 内置 HTTP 服务，一次性令牌鉴权
- **在线发布** — 经 Cloudflare 一键发布到公网
- **iOS 伴侣** — 在手机上通过 iCloud 编辑、聊天、发布
- **放映模式与专注模式**，HTML / PDF / 2× PNG 导出，预览主题（GitHub / Nord / Dracula）
- **Sparkle 自动更新** — 安装包见 [meditorapp.pages.dev](https://meditorapp.pages.dev)

---

## 📋 系统要求

- **macOS** 14.0+ (Sonoma)
- **Xcode** 15.0+（开发用）
- **Swift** 5.9+

## 🔧 构建与运行

### 快速启动

```bash
# 克隆仓库
git clone https://github.com/retrychx/Meditor.git
cd Meditor

# 使用 SPM 构建
swift build

# 直接运行（轻量模式，无应用图标）
swift run
```

### 运行测试

```bash
# 自动使用完整 Xcode toolchain
./scripts/test.sh

# 更短的别名
make test
```

### 生成 .app 包

```bash
# 构建后打包为 .app
swift build
bash scripts/bundle.sh

# 启动（带图标、Dock 驻留、文档类型关联）
open .build/debug/MEditor.app
```

> **注意：** `bundle.sh` 会自动对 `.app` 包进行 ad-hoc 签名。打开一次后，即可在任意 `.md` 或 `.html` 文件上使用 **显示简介 → 打开方式 → MEditor → 全部更改** 来关联文件类型。

### 版本号

每个平台的版本号都有唯一来源——**版本号在这里改**：

- **macOS**：编辑仓库根目录的 [`VERSION`](VERSION)。`scripts/bundle.sh` 打包时会把它注入 `MEditor.app` 的 `Info.plist`（`Sources/MEditor/Info.plist` 里的版本号只是占位符）。
- **iOS**：编辑 `Mobile/MEditorMobile.xcodeproj` 的构建设置 `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`。`Mobile/MEditorMobile/Info.plist` 通过 `$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)` 引用它们。

运行 `make version` 可查看当前版本号和上述提示。

### 在 Xcode 中打开

```bash
open Package.swift
```

---

## ⚙️ AI 设置

打开 **设置（⌘,）→ AI**，选择一种后端：

| 后端 | 需要什么 |
|------|----------|
| OpenAI 兼容预设 | 从 8 家预设（OpenAI、DeepSeek、Kimi、GLM、通义千问、OpenRouter、Groq、Ollama）中选一个，填入 API Key，选模型 |
| Anthropic | API Key + 模型（如 `claude-opus-4-5`） |
| Claude CLI | 什么都不用 —— 直接复用本机 Claude Code 登录态 |
| 自定义端点 | 任何 OpenAI 兼容的 Base URL + Key + 模型 |

没有 key？选 Claude CLI 后端，零配置跑起来。

---

## 🏗 项目结构

```
MEditor/
├── Package.swift
├── scripts/
│   ├── bundle.sh          # .app 包组装脚本
│   └── test.sh            # Xcode toolchain 测试脚本
├── docs/                  # 设计文档与历史分析
├── plans/                 # 进行中的开发计划
└── Sources/MEditor/
    ├── Models/            # EditorTab、FileItem、AgentTool、PluginSkill…
    ├── Protocols/         # FileService、SyntaxHighlight、AgentContext…
    ├── Services/
    │   ├── AI/
    │   │   ├── Agent/
    │   │   │   ├── AgentRunner.swift          # 多轮循环与状态
    │   │   │   ├── CommandSandbox.swift       # 风险分级的 Shell 沙盒
    │   │   │   ├── AgentHistoryBudget.swift   # 上下文 token 预算
    │   │   │   ├── Backends/
    │   │   │   │   ├── AgentBackend.swift     # 协议 + 默认流式回退
    │   │   │   │   ├── RestAgentBackend.swift # OpenAI 与 Anthropic SSE
    │   │   │   │   └── ClaudeCLIBackend.swift # claude CLI 子进程
    │   │   │   └── Tools/                     # 文档、编辑器、工作区、Shell 工具
    │   │   ├── InlineEditAgent.swift          # 选区级修改 + diff 审阅
    │   │   ├── AIService.swift                # 对话补全与 provider 预设
    │   │   └── BeautifyAgent.swift            # 单发文档润色
    │   ├── Core/          # AppSettings、Localization、MarkdownFormatter
    │   ├── File/          # FileService、FileWatcher、文件类型配置
    │   └── Calendar/      # CalendarService（EventKit）
    ├── Managers/          # Tab、FileTree、Share、Template、Todo…
    └── Views/
        ├── Agent/         # AgentStepView、AgentResultPanel
        ├── AI/            # AIAssistant、@mention 输入器
        ├── Editor/        # NativeEditorView、TabBar、InlineEdit…
        ├── Preview/       # MarkdownWebPreview、TOC、ExportBar
        ├── Sidebar/       # FileSidebar、FileRow、TodoSidebar…
        └── Shared/        # DesignTokens、ChromeButton、Toast…
```

---

## 🗺 路线图

执行顺序以 [`plans/2026-08-18-agent-workstation-plan.md`](plans/2026-08-18-agent-workstation-plan.md) 为准。

**已交付**
- [x] 真 Agent：14 个工具、多轮循环、三种后端（OpenAI 兼容 / Anthropic / Claude CLI）、BYOK
- [x] Agent 加固：写文件确认、命令沙盒风险分级、上下文预算、停滞检测、只读工具并行、用量显示
- [x] 行内编辑 diff 审阅、`@mention` 上下文、多会话历史
- [x] 局域网分享 + Cloudflare 在线发布
- [x] iOS 伴侣（iCloud 编辑 / 聊天 / 发布）
- [x] 放映与专注模式、HTML 导出、预览主题、Sparkle 自动更新

**下一步**（Phase 1–3）
- [ ] Onboarding —— 首启引导、零配置 Claude CLI 默认后端、脚本化演示
- [ ] 全局搜索（⌘⇧F）—— 建在共享工作区索引上，同时供 Agent 搜索与快速打开使用
- [ ] Agent 运行一键回滚（run 级检查点）

**后续**（Phase 4–6）
- [ ] Spotlight 索引与 Quick Look 插件、Shortcuts intents
- [ ] MCP Server —— 把 Agent 工具暴露给 Claude Desktop / Cursor
- [ ] 诊断中心 —— 死链、缺图、标题层级检查

---

## 🤝 参与贡献

欢迎提 PR，提交前请先跑 `make test`。

---

## 📄 开源协议

[MIT](LICENSE)

---

*用心打造 · 纯原生 macOS 体验*
