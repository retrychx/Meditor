# MEditor 代码质量评审与功能路线图

> ⚠️ **本文已过时（标注于 2026-08-18）**：这是 2026-05-26 初版（Agent 出现之前）的评审快照。§2 功能路线图与代码统计（23 文件 / ~1,350 行、"无单元测试"）均已不反映现状——MEditor 现在是带 14 工具 Agent 的文档工作台，测试套件已补齐。当前定位与执行顺序以 [`plans/2026-08-18-agent-workstation-plan.md`](../plans/2026-08-18-agent-workstation-plan.md) 为准。文中列出的多项问题（无测试、无偏好设置、无会话恢复等）此后已修复。

> 评审日期：2026-05-26
> 项目版本：初版（MarkEdit → MEditor 重命名后）

---

## 项目概览

| 维度 | 数据 |
|------|------|
| Swift 源文件 | 23 个，共 1,350 行代码 |
| HTML/CSS/JS 资源 | 4 个文件（~2,700 行，含嵌入样式和 JS 库） |
| 架构层次 | Models / Protocols / Services / ViewModels / Views |
| 编译状态 | ✅ 零错误零警告 |
| macOS 目标 | 14.0+ (Sonoma) |
| SPM 依赖 | swift-markdown-ui, Splash（已不用） |

---

## 一、代码质量分析

### ✅ 优点

**1. 架构设计清晰**
- Protocol 层抽象到位 — `FileServiceProtocol` / `SyntaxHighlightEngine` 方便测试和扩展
- Service 注册模式 — `HighlightService.shared.register()` 易于添加新的语言引擎
- `@Observable` macro 替代 Combine，状态管理简洁

**2. 性能边界考虑全面**
- 大文件（>500KB）跳过 regex 高亮，防止 UI 冻结
- 内容更新 50ms 防抖 + 高亮 300ms 防抖，打字不卡顿
- Mermaid XSS 防护使用 JSON encoder 而非字符串拼接
- 滚动双向同步的防循环机制（`isProgrammaticScroll` 标记 100ms 重置）

**3. macOS 原生风格**
- 使用 `NSVisualEffectView` / `NSTextView` / `WKWebView` 等原生组件
- 支持 macOS 深色/浅色模式自适应
- 拖拽分隔线手势热区（6px）与视觉线（1px）分离，交互细致

**4. 代码组织合理**
- 目录结构与职责对应清晰
- 命名一致，SwiftUI + AppKit 边界明确

---

### ⚠️ 待改进问题

#### 中优先级

| # | 问题 | 文件 | 说明 |
|---|------|------|------|
| 1 | **HTML/JS/CSS 嵌入 Swift 字符串** | `MarkdownWebPreview.swift` | ~300 行的 CSS+JS+HTML 以 `"""` 字面量嵌入，难以维护和版本管理。应抽为独立 `.html` 模板文件，运行时替换占位符 |
| 2 | **资源复制代码重复** | `MarkdownWebPreview.swift:386-413` | `prepareResources()` 中 3 个 JS 文件的复制逻辑完全一致，可用数组循环或 `copyIfNeeded` 方法抽取 |
| 3 | **FileSidebar List 重复** | `FileSidebar.swift:61-96` | 搜索模式和非搜索模式的 List 代码几乎完全一样，只有数据源不同，可合并为一个条件数据源 |
| 4 | **Bundle ID 残留** | `FileWatcherService.swift:16` | GCD 队列 label 仍为 `com.markedit.filewatcher`，应改为 `com.meditor.filewatcher` |
| 5 | **Cache 目录硬编码** | `MarkdownWebPreview.swift:375` | `com.markedit.preview` 同样残留旧 bundle ID |

#### 低优先级

| # | 问题 | 文件 | 说明 |
|---|------|------|------|
| 6 | **`try?` 静默失败** | `MarkdownWebPreview.swift:383-411` | JS 文件复制失败时无反馈，预览可能空白但用户看不到错误 |
| 7 | **`openFolder()` 重复** | `MEditorApp.swift` + `ContentView.swift` | 两处有几乎一样的 `NSOpenPanel` 逻辑，可抽取为共享方法 |
| 8 | **WKWebView 延迟释放** | `WebPreviewView.swift` | 未实现 `dismantleNSView`，WebView 内存不会及时回收 |
| 9 | **高亮主题硬编码** | `MarkdownWebPreview.swift:89-120` | GitHub 主题 CSS 嵌入在 Swift 中，用户无法切换 |
| 10 | **编辑器字体 14pt 硬编码** | `NativeEditorView.swift:29,177` | 用户无法调整字体和字号 |
| 11 | **无单元测试** | — | 整个项目零测试文件 |

---

## 二、功能路线图

### P1 — 核心补齐（建议优先做）

| 功能 | 说明 | 工作量 |
|------|------|--------|
| **应用图标** | 目前为空白默认图标，需配 `.icns` | ~1h |
| **文档类型关联** | `Info.plist` 中注册 `.md` 文件类型，双击用 MEditor 打开 | ~1h |
| **编辑器字体/字号设置** | 偏好面板，支持调整字体、字号、行高 | ~3h |
| **偏好设置窗口** | 使用 `Settings` Scene（`SettingsLink`），放置字体、主题、自动保存选项 | ~2h |
| **自动保存 + 会话恢复** | 退出时记住打开的文件列表和未保存内容，启动自动恢复 | ~4h |
| **HTML 模板抽取** | 将内嵌的 HTML/CSS/JS 抽为独立模板文件 | ~2h |

### P2 — 体验增强

| 功能 | 说明 | 工作量 |
|------|------|--------|
| **Git 状态指示** | 侧栏文件旁显示 `M`/`A`/`?` 等状态标记 | ~5h |
| **全局搜索** | `⌘⇧F` 递归搜索项目文件内容，显示匹配行 | ~6h |
| **目录导航（Outline）** | 侧栏新增 Outline 面板，解析 `##` 标题生成目录树 | ~4h |
| **图片粘贴/拖入** | 从剪贴板粘贴图片 → 自动保存到 `assets/` → 插入 `![](...)` | ~3h |
| **代码折叠** | NSTextView 原生支持，增加折叠标记和交互 | ~5h |
| **导出为 PDF/HTML** | 将 Markdown 导出为 PDF 或独立 HTML 文件 | ~2h |

### P3 — 锦上添花

| 功能 | 说明 | 工作量 |
|------|------|--------|
| **多窗口支持** | 每个窗口独立状态，`WindowGroup` + `openWindow` | ~6h |
| **Vim 模式** | 嵌入 vim 按键映射 | 大 |
| **CSV/JSON/Log 预览** | 格式化展示非 Markdown 文件 | ~4h |
| **打字机模式** | 编辑时当前行始终居中（iA Writer 风格） | ~3h |
| **字数统计** | 状态栏可选显示单词/字符/行数 | ~1h |
| **Minimap** | 编辑器右侧缩略图导航 | 大 |
| **主题市场** | 用户可下载/切换编辑器高亮主题 | 大 |

---

## 三、总体评价

**7 / 10**

作为初版项目，架构选型合理（SwiftUI + Observation + WKWebView），关键性能边界考虑到了，功能覆盖了 Markdown 编辑器的核心需求。

**最值得先做**：
1. 将 HTML 模板从 Swift 字符串中抽离（后续修改样式轻松 10 倍）
2. 配应用图标和文档类型关联
3. 加偏好设置界面
