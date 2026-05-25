# MEditor — 产品方向分析

> 分析日期：2026-05-26
> 当前版本：Initial release（MarkEdit → MEditor 更名后）

---

## 总览

本文档分析 MEditor 四个产品方向，评估其用户价值、实现复杂度、维护成本，并给出优先级排序。

| 优先级 | 方向 | 核心价值 | 预估工时 |
|--------|------|----------|----------|
| **P0** | ② 保存为模板 | 直接满足日常高频需求 | ~3-6h |
| **P1** | ① HTML ↔ MD 互转 | 打开新使用场景，但边界情况多 | ~8-12h |
| **P2** | ③ 代码块交互增强 | 提升预览阅读体验 | ~4-6h |
| **P3** | ④ 预览主题切换 | 纯视觉偏好，非必需 | ~3-5h |

---

## 方向一：HTML ↔ Markdown 双向转换

### 用户价值

WYSIWYG 富文本编辑器已成为许多用户的默认写作工具。允许用户在 HTML 和 Markdown 之间自由转换，可以：
- 从网页/邮件/文档粘贴富文本 → 自动转成 MD 格式继续编辑
- 将写好的 MD 导出为格式化 HTML（带内联样式），直接用于邮件、博客发布
- 降低新用户从 Word/Google Docs 迁移到 Markdown 的门槛

### 技术方案：turndown.js + 自定义 HTML 序列化

#### MD → HTML（已有能力）

当前预览已经用 `marked.js` 实现了 MD → HTML 渲染。导出完整 HTML 只需：
- 用 `marked.parse(content)` 渲染 HTML
- 包裹完整文档结构（`<html><head><style>` + highlight.js 主题样式 + 内联 CSS）
- 提供「复制 HTML」和「导出 .html 文件」两个入口

#### HTML → MD（核心新增）

使用 **[turndown.js](https://github.com/mixmark-io/turndown)**：

```js
const turndownService = new TurndownService({
  headingStyle: 'atx',       // ## 风格
  codeBlockStyle: 'fenced',  // ``` 代码块
  emDelimiter: '*'           // *斜体*
})
```

turndownService 已内置于资源目录中（`Resources/Preview/`），与应用打包。在 WKWebView 中通过 `WKUserScript` 注入或通过 `evaluateJavaScript` 调用。

#### 边界情况处理

| 场景 | 处理策略 |
|------|----------|
| **复杂嵌套表格** | turndown 默认不支持 → 回退为 HTML 保留，不做转换 |
| **inline styles 和 class** | 用 turndown plugin 匹配常见样式（`text-align: center` → `<center>`） |
| **Mermaid 图表** | 检测 `<pre><code class="language-mermaid">` → 保留为 mermaid 代码块 |
| **空链接 / 占位符** | 过滤 `javascript:void(0)` 等无效链接 |
| **Base64 图片** | 提示用户「包含内嵌图片，是否保存到 assets/？」 |
| **数学公式 MathJax** | 当前项目无此支持，暂不做处理 |
| **超长输入** | 超过 1MB 内容提示「内容过长，可能影响性能」 |

#### 交互设计

```
┌─────────────────────────────────────┐
│  编辑器工具栏                        │
│  [导入 HTML]  [导出 HTML]  [复制 MD] │
└─────────────────────────────────────┘

点击「导入 HTML」→ 粘贴/文件选择 → preview 显示转换预览 → 确认插入
点击「导出 HTML」→ 生成完整 HTML → 保存面板 / 复制到剪贴板
```

**关键决策**：HTML → MD 转换应该在 WKWebView 中（JS 侧）完成，还是通过 macOS 的 Swift 侧调用？

- **JS 侧**：直接调用 turndown.js，异步返回结果。优势是无需跨进程通信，劣势是难以处理大文件
- **Swift 侧**：通过 `WKWebView.evaluateJavaScript` 调用。推荐方案——利用已有 webview 上下文，无额外依赖

### 实现要点

1. 将 turndown.js 加入 `Resources/Preview/` 目录
2. 在 `MarkdownWebPreview.swift` 新增 `exportHTML()` 和 `importHTML()` 方法
3. 工具栏应只在「当前有打开文件」时显示转换按钮
4. **注意**：转换是「一次性操作」，不是「实时同步」——用户操作后才触发

---

## 方向二：保存为模板 ⭐ 推荐 P0

### 用户价值

用户经常重复使用某些 Markdown 结构：
- 周报/日报模板
- 会议记录模板（参会人、议程、决议）
- 博客文章头部（frontmatter）
- 项目 README 骨架

保存为模板 ≈ 一键生成文件骨架，高频、低认知成本。

### A 方案：轻量级（推荐）

| 特性 | 说明 |
|------|------|
| **触发入口** | 右键 sidebar → 「另存为模板」，或 `⌘⇧S` |
| **存储方式** | `~/Library/Application Support/com.meditor/templates/` 目录下的 `.md` 文件 |
| **管理方式** | sidebar 底部新增「模板」分页或侧栏节 |
| **新建文件** | 点击「从模板新建」→ 选择模板 → 在当前目录创建副本 |

### B 方案：占位符变量（高级）

在 A 方案基础上，支持 `{{title}}`、`{{date}}`、`{{author}}` 等占位符，新建时弹窗填写。

```
---
title: {{title}}
date: {{date}}
author: {{author}}
tags: []
---

## {{title}}

### 背景

### 方案

### TODO
```

#### B 方案使用频率评估

| 用户类型 | 是否会用到占位符 |
|----------|-----------------|
| 轻度用户（写笔记、README） | ❌ 大概率不会 |
| 中等用户（周报、会议记录） | ⚠️ 可能会，但也能手动改 |
| 重度用户（批量生成、自动化） | ✅ 高频需求 |

**建议**：先做 A 方案（纯文本模板保存/读取），A 完成后看用户反馈再决定是否加 B。

### 实现要点

1. **模板目录管理**：`FileManager.default.urls(for: .applicationSupportDirectory, ...)` + `com.meditor/templates/`
2. **减少与现有系统的耦合**：模板系统应该是独立的，不依赖 `EditorTab` 或 `FileItem`
3. **模板预览**：点击模板时在预览区显示渲染效果
4. **默认模板**：内置 "空白文档"、"README 骨架"、"会议记录" 三个默认模板

---

## 方向三：代码块交互增强

### 用户价值

阅读技术文档时，经常需要复制代码块中的代码。当前用户需要手动选中文本 → 复制。增强后直接点击按钮即可。

### 功能列表

| 子功能 | 交互 | 实现方式 |
|--------|------|----------|
| **复制按钮** | 代码块右上角悬浮 `📋` 图标 | JS: `navigator.clipboard.writeText()` |
| **折叠/展开** | 长代码块默认折叠，显示行数 | CSS `max-height` + JS toggle |
| **语言标签** | 代码块左上角显示 `javascript` / `python` 等 | 从 `<code class="language-xxx">` 提取 |
| **行号显示** | 代码左侧显示行号 | `highlight.js` 自带 `hljs.lineNumbers()` 插件 |

### 注意事项

1. **clipboard API 限制**：`navigator.clipboard.writeText` 需要 `https` 或 `localhost` 环境。MEditor 使用 `file://` 协议 → **不可用**。替代方案：
   - WKWebView 中注入 JS → `window.webkit.messageHandlers.copyCodeBlock.postMessage(code)` → Swift 侧通过 `NSPasteboard.general` 复制
   - 这不影响实现复杂度，但需要 JS → Swift 桥接

2. **折叠状态与滚动同步**：如果代码块被折叠，`scrollHeight` 变化可能干扰双向滚动同步。需要在折叠/展开时触发 `scrollSync` 重算

3. **highlight.js 版本兼容**：当前使用的 highlight.js 版本是否支持 `lineNumbers()` 插件？如需升级需测试

### 交互原型

```
┌──────────────────────────────────┐
│ javascript         [📋] [▼]      │  ← 语言标签 + 操作按钮
│──────────────────────────────────│
│  1 │ function hello() {          │
│  2 │   console.log("world")      │
│  3 │ }                           │
└──────────────────────────────────┘
```

---

## 方向四：预览主题切换

### 用户价值

不同用户对 Markdown 渲染风格有不同的审美偏好：
- 有的喜欢亮白干净（iA Writer 风格）
- 有的喜欢深色护眼（Dracula / Nord）
- 有的需要对比度高的（用于投影/演示）

### 推荐五个主题

| # | 主题名 | 风格 | 适用场景 |
|---|--------|------|----------|
| 1 | **GitHub** | 类 GitHub Markdown 渲染风格 | 默认/通用，当前已有 |
| 2 | **Nord** | 冷色系低对比度 | 长时间阅读、暗色模式 |
| 3 | **Dracula** | 高饱和度紫粉色调 | 技术写作者、炫酷风格 |
| 4 | **iA Writer** | 极简、大留白、无边框 | 专注写作 |
| 5 | **Solarized Light** | 暖色低对比度 | 日间阅读、护眼 |

### 技术实现

当前预览 CSS 嵌入在 `MarkdownWebPreview.swift` 的 Swift 字符串中（~300 行）。切换主题需要：

1. **短期（低成本）**：将 CSS 提取为独立 `.css` 文件放入 `Resources/Preview/themes/`
2. **中期**：通过 `WKUserScript` 注入 `document.getElementById('theme-style').href = 'theme-nord.css'` 实现热切换
3. **存储**：用户偏好通过 `UserDefaults` 持久化，启动时从 `AppState` 读取

### 低成本替代方案

> **不做跨主题设计系统**，只做 CSS 变量替换即可。

```
:root {
  --bg-primary: #ffffff;       /* Nord: #2e3440 */
  --text-primary: #24292e;     /* Nord: #d8dee9 */
  --code-bg: #f6f8fa;         /* Nord: #3b4252 */
  --link-color: #0366d6;      /* Nord: #81a1c1 */
  --border-color: #e1e4e8;    /* Nord: #4c566a */
}
```

如果每个主题只是 CSS 变量替换，甚至可以不打包 5 个独立 CSS 文件，而是在 Swift 侧存储 5 组颜色值，构建时动态生成 CSS。但这会使预览渲染依赖 JS 执行，不如直接换 CSS 文件高效。

### 注意事项

- 主题切换不应导致页面闪烁（白屏 → 新主题）
- 暗色模式应自动匹配系统暗色/亮色状态（`colorScheme`），每当前置条件下有两个变体
- Mermaid 图表主题也需跟随（mermaid.init 的 theme 参数）

---

## 四个方向的串联关系

```
                    ┌─────────────────────┐
                    │     ② 保存为模板     │
                    │  (P0 - 最高优先级)   │
                    └────────┬────────────┘
                             │
              ┌──────────────┼──────────────┐
              │              │              │
              ▼              ▼              ▼
   ┌─────────────────┐ ┌──────────┐ ┌──────────────┐
   │ ① HTML ↔ MD 互转 │ │ ③ 代码块  │ │ ④ 预览主题   │
   │ 模板使用后的自然  │ │ 交互增强  │ │ 切换         │
   │ 延伸需求          │ │ 提高阅读  │ │ 视觉体验     │
   └─────────────────┘ │ 效率      │ │ 个人化       │
                        └──────────┘ └──────────────┘
   ══════ 强关联：模板的内容往往来自网页/富文本 → 需要 HTML 导入
   ════   弱关联：独立性较强，可各自开发
   ═══    弱关联：模板预览和主题样式共享 CSS 系统
```

### 推荐实施顺序

```
② → ① → ③ → ④
```

**理由：**
1. **② 保存为模板** — 用户价值最高、实现最简单（纯文件操作 + 少量 UI），快速获得正向反馈
2. **① HTML ↔ MD 互转** — 与模板系统协同（模板内容常来自网页），但实现复杂度较高，需要 turndown.js 集成和边界情况处理
3. **③ 代码块交互增强** — 纯前端增强，不依赖其他系统，技术风险低，但 JS → Swift 桥接需要额外测试
4. **④ 预览主题切换** — 纯视觉美化，优先级最低。建议等到 CSS 模板提取重构完成后再做

---

## 附录：关于 MarkEdit 原始项目

MEditor 源自开源项目 [MarkEdit](https://github.com/MarkEdit-app/MarkEdit)，在原项目基础上做了大量重构和方向调整：

| 维度 | MarkEdit | MEditor |
|------|----------|---------|
| 架构 | NSDocument-based + WebView editor | **SwiftUI + NSTextView native editor + WKWebView preview** |
| 编辑器 | WebView 内的 CodeMirror | **原生 NSTextView + macOS 原生体验** |
| UI 框架 | AppKit | **SwiftUI 为主 + AppKit 辅助** |
| 定位 | 类 MacVim 的代码编辑器 | **Markdown/HTML 写作与阅读工具** |

MEditor 的产品方向应该围绕 **「写作体验」** 而非 **「代码编辑」** 展开，上述四个方向均以此为核心。
