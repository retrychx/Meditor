# MEditor 项目评估与路线图

> 更新日期：2026-05-26
> 版本：v0.4（明确"预览为主、编辑为辅"的定位，重排预览质量优先路线）

---

## 一、当前状态速览

| 维度 | 数据 |
|------|------|
| 产品定位 | **预览优先的本地文档查看器**（编辑是次要修补能力） |
| Swift 源文件 | 23 个，~1,350 行 |
| 嵌入资源 | HTML/CSS/JS ~2,700 行（含 marked / highlight / mermaid） |
| 编译状态 | ✅ 零错误零警告 |
| 测试覆盖 | ❌ 单元测试无法在命令行运行（需 Xcode） |
| macOS 目标 | 14.0+ (Sonoma) |
| 预览刷新策略 | 打开文件 / 保存文件 / 外部修改触发，**不在打字时刷新** |
| 已知运行时缺陷 | 5 个（已修），见 §3 |

---

## 二、架构概览

```
MEditorApp (SwiftUI App)
  └─ ContentView (布局：Sidebar + Editor + Preview)
       ├─ FileSidebar (List + 搜索)
       ├─ EditorView
       │    ├─ EditorTabBar
       │    └─ NativeEditorView (NSTextView 包装)
       └─ PreviewPanel
            ├─ MarkdownWebPreview (WKWebView + marked.js)
            └─ WebPreviewView (HTML 直接预览)

AppState (@Observable)
  ├─ fileTree / openTabs / selectedTabID
  ├─ previewContent / previewLanguage
  └─ FileService (协议) + FileWatcherService (FSEvents)

HighlightService
  ├─ MarkdownHighlightEngine (NSRegex)
  └─ HTMLHighlightEngine    (NSRegex)
```

**架构判断**：分层合理。`@Observable` 替代 Combine 简洁。Service 层抽象到位（可换实现、可测）。SwiftUI ↔ AppKit 边界清晰。

---

## 三、运行时缺陷清单（已修复）

> 这些是首版 review 漏掉的真实闪退/异常，全部由实际操作中发现并修复。

### P0 - 致命

| # | 问题 | 文件 | 现象 | 根因 | 修复 |
|---|------|------|------|------|------|
| R1 | 打开 md 文件秒闪退 | `NativeEditorView.swift` | 点击侧栏文件即闪退 | `updateNSView` 中 `textView.string = content` 触发 `textDidChange` → `onContentChange` → 修改 `@Observable` 属性 → 又触发 `updateNSView` → 无限递归栈溢出 | 设置 `textView.string` 前后包裹 `isProgrammaticChange = true/false` 阻断回调 |
| R2 | FileWatcher 类型不匹配 | `FileWatcherService.swift` | 偶发崩溃 | `[UnsafePointer<Int8>]` 强转 `CFArray`，CF 期望的是 CFString 数组 | 改为 `urls.map { $0.path } as CFArray` |
| R3 | 预览资源复制失败 | `MarkdownWebPreview.swift` | 第二次启动后预览空白 | `copyItem` 在文件已存在时抛错被 `try?` 吞掉 | 抽出 `copyIfNeeded`：先 `removeItem` 再 `copyItem` |

### P1 - 体验

| # | 问题 | 文件 | 现象 | 修复 |
|---|------|------|------|------|
| R4 | WKWebView 缓存导致预览不刷新 | `MarkdownWebPreview.swift` | 保存后预览不变 | `loadFileURL` 时给 URL 加时间戳 query 破坏缓存 |
| R5 | 实时刷新预览造成闪烁 | `AppState.swift` | 输入时 webview 频繁重载 | 改为只在 `saveTab` 成功后更新 `previewContent`（保存触发预览） |

### 教训

> 这 5 个问题都不是结构性的，单纯静态扫描代码看不出来——必须打开应用走一遍流程。
> 后续任何 review 应该包含**至少一次"打开文件 → 编辑 → 切换 → 保存"的端到端验证**。

---

## 四、代码质量评估

### ✅ 做得好的地方

- **大文件性能边界**：`NativeEditorView.largeFileThreshold = 500KB`，超出跳过 regex 高亮，防止 UI 冻结
- **打字防抖**：内容更新 50ms + 高亮 300ms 双层防抖
- **XSS 防护**：mermaid 注入用 `JSONEncoder` 而非字符串拼接
- **拖拽分隔线**：6px 命中区 vs 1px 视觉线分离，是细节
- **Protocol 层抽象**：`FileServiceProtocol` / `SyntaxHighlightEngine` 利于测试和扩展

### ⚠️ 真正的债务（按优先级）

| # | 类别 | 文件 | 问题 | 影响 |
|---|------|------|------|------|
| D1 | **维护性** | `MarkdownWebPreview.swift` | ~300 行 HTML/CSS/JS 内嵌 Swift 字符串字面量 | 改样式要修 Swift 代码、无 IDE 高亮、无版本控制 diff 友好性 |
| D2 | **产品模型** | `ContentView.swift` `MEditorApp.swift` `AppState.swift` | UI 是 folder-first，但真实需求是 doc-first（双击/拖入单个 md/html 即看） | 入口不顺，和 AI 时代临时查看文档的主场景错位 |
| D3 | **预览渲染** | `MarkdownWebPreview.swift` | 每次刷新都整页 reload WKWebView，闪烁明显，滚动位置丢失 | 体验上不像"高质量预览器"，与产品核心定位有差距 |
| D4 | **架构** | `AppState.swift` | "状态" + "服务" + "协调" 全在一个类里（260 行） | 测试需 mock 整个 state；新增功能容易让这个类继续膨胀 |
| D5 | **生命周期** | `WebPreviewView.swift` / `MarkdownWebPreview.swift` | 未实现 `dismantleNSView`，WKWebView 关闭后不释放 | 长期使用内存上涨 |
| D6 | **资源管理** | `MarkdownWebPreview.swift` | preview HTML 写入 caches 目录，没清理机制 | 长期占用磁盘 |
| D7 | **可配置性** | `NativeEditorView.swift` | 字体 14pt 硬编码、配色硬编码 | 用户无法调整 |
| D8 | **代码重复** | `FileSidebar.swift` | 搜索/非搜索两份 List 代码几乎一样 | 修一处忘另一处的风险 |
| D9 | **品牌一致性** | `FileWatcherService.swift` `MarkdownWebPreview.swift` | `com.markedit.*` 的 GCD label 和缓存目录残留 | 与新名字 MEditor 不一致 |
| D10 | **可观测性** | 全局 | 无日志系统，错误只通过 `errorMessage` Alert 暴露 | 排查问题靠用户截图 |
| D11 | **测试** | — | 仅有 5 个测试文件，且 SPM 命令行无法运行（需 XCTest） | 重构无回归保障 |

### 不重要但常被列出的伪问题

下面这些在原 review 文档里被列为"待改进"，实际可以忽略：

- ~~`try?` 静默失败~~ — Swift 风格问题，不是 bug
- ~~`openFolder()` 重复定义两处~~ — 总共 6 行代码，抽不抽都行
- ~~Markdown 高亮主题硬编码~~ — 这是默认值，不是问题

---

## 五、产品定位确认

MEditor 的核心方向应明确为：

> **预览优先的本地文档查看器 / 轻编辑器**

不是通用 IDE，也不是模板平台，更不是创作型 Markdown 编辑器。它是一个 **专门服务于"快速看 md/html 文档效果"的本地工具**，编辑能力是次要的修补功能。

### 核心价值

| 维度 | 定义 |
|------|------|
| 主要功能 | **预览** — 打开文件即看到完整渲染效果 |
| 次要功能 | 轻量编辑（修标题、改段落、调代码块、补图片、改链接） |
| 触发预览刷新 | 打开文件 / 保存（⌘S） / 外部修改（FSEvents） |
| **不做** | 打字时实时刷新预览（避免闪烁、滚动跳动、心智成本） |
| 不优先做 | 深度编辑器能力、复杂模板系统、所见即所得 |

### 这一定义意味着什么

1. **预览质量是产品的脸面**：渲染效果、字体、代码高亮、Mermaid 图、暗色适配，每一项都直接决定产品是否"值得打开"
2. **编辑是辅助而非核心**：用户大多数时间在「看」而不是在「写」。重度写作场景应该让位给 Typora / iA Writer
3. **保存触发刷新是有意设计**：和"打字即时刷新"的所见即所得型编辑器明确区分，避免闪烁与心智疲劳
4. **文档优先于文件夹**：双击 `.md/.html`、拖入单个文件、临时打开 LLM 输出内容，应当是头号入口
5. **导出/复制路径要顺**：把预览效果"带走"（导出 HTML/PDF、复制代码块、保存截图）和"看清楚"同样重要

### 不是什么

- 不是 AI 集成工具（不内置 LLM API、不做生成）
- 不是知识库（不做双链、标签、库管理）
- 不是协作工具（不做多人编辑、评论）
- 不是发布平台（不做博客托管、SEO）

---

## 六、产品方向重排

原产品分析文档把重点放在 `模板系统 → HTML↔MD 互转 → 代码块增强 → 主题切换`，更像"内容复用工具"路线。
基于"预览优先"的定位，真正的主线应该是：

> **先把"打开即可读、保存即更新、看完能带走"做扎实，再补编辑增强能力。**

### 关键事实

1. 当前项目最大的资产是 `Markdown/HTML → 渲染预览` 这条链路
2. 「保存触发预览刷新」是经过权衡的设计选择，不是要修复的缺陷
3. 当前 UI 是 folder-first（必须 Open Folder 才能进主流程），但实际场景常常是临时打开单个 `.md/.html`
4. 真正影响"预览质量"的问题：整页 reload 闪烁、缺主题切换、缺导出 — 这些才是核心债务

### 新的优先级

```
                    MEditor 路线图
                        │
        ┌───────────────┼───────────────┐
        ▼               ▼               ▼
   P0 预览质量      P1 文档入口闭环     P2 轻编辑增强
   ──────────       ─────────────      ──────────
   HTML 模板抽离     单文件双击/拖入     代码块复制按钮
   减轻整页 reload   应用图标 + 文档关联 Outline 目录
   预览主题切换      会话恢复            图片粘贴/拖入
   导出 HTML / PDF   WKWebView 释放     字体/字号偏好
                                      Frontmatter 修整

   P3 谨慎评估
   ──────────
   模板系统
   HTML ↔ MD 双向转换
   Vim 模式 / Minimap / 打字机模式
   多格式预览扩张（CSV/JSON 等）
```

### 与旧方向的对照

| 方向 | 旧判断 | 新判断 | 理由 |
|------|--------|--------|------|
| HTML 模板抽离 | 中优先级 | **P0** | 不抽离，主题切换 / 暗色适配 / 模板修补都做不动 |
| 减轻整页 reload | 默认接受 | **P0** | 保存刷新本身没问题，但每次都 reload 闪烁明显——可改为 JS 注入更新内容区 |
| 预览主题切换 | P3 | **P0** | 与"预览是脸面"定位强相关 |
| 导出 HTML / PDF | P2 | **P0** | 预览看完要能"带走"，是核心闭环 |
| 单文件打开 / 双击 / 拖入 | 未突出 | **P1** | folder-first 与实际使用方式错位 |
| 应用图标 + Info.plist 文档关联 | 未列入产品方向 | **P1** | 1h 即可完成，立即提升观感 |
| 代码块复制按钮 | P2 | **P2** | 高频但不是预览本身 |
| Outline / 图片粘贴 | P2/P3 | **P2** | 都是"轻编辑"层 |
| 模板系统 | P0 | **P3** | 0 用户产品做模板是过早优化 |
| HTML ↔ MD 互转 | P1 | **P3** | 边界复杂，且不在"预览"链路上 |

---

## 七、推荐执行计划

### Sprint 1（本周）— 把"预览质量"做成产品的脸面

| 任务 | 工作量 | 价值 |
|------|--------|------|
| 抽 HTML/CSS/JS 为独立模板文件 | 4h | 解锁主题切换、暗色适配、模板修补，是后面所有预览能力的底座 |
| 减轻整页 reload（DOM diff 或 innerHTML 替换） | 4h | 保存刷新不再闪烁，滚动位置保留 |
| 预览主题切换（GitHub / Nord / Dracula 三套足够） | 4h | 抽离模板后顺势完成 |
| 导出 HTML / PDF（WKWebView API） | 3h | 「看完能带走」的核心闭环 |
| 应用图标 + Info.plist 文档类型关联 | 1h | 双击 .md 用 MEditor 打开、应用图标可识别 |
| WKWebView `dismantleNSView` + 预览缓存清理 | 1h | 长期稳定，不积累临时文件 |
| 清理 `com.markedit.*` 残留 | 0.3h | 品牌一致 |
| **小计** | **~17h** | |

### Sprint 2 — 文档入口闭环 + 高频轻编辑

| 任务 | 工作量 | 价值 |
|------|--------|------|
| 单文件双击 / 拖入 / Open File 打开 | 3h | 从 folder-first 调整为 doc-first |
| 代码块复制按钮（JS↔Swift bridge） | 4h | 技术文档高频动作 |
| Outline 目录树 | 4h | 长文档快速跳转 |
| 自动保存 + 会话恢复 | 4h | 临时多文件切换不丢状态 |
| 图片粘贴/拖入并自动落盘 | 3h | 修补型编辑的主要场景 |
| **小计** | **~18h** | |

### Sprint 3 — 偏好与体验增强

| 任务 | 工作量 |
|------|--------|
### Sprint 3 — 偏好与体验增强

| 任务 | 工作量 |
|------|--------|
| 偏好设置窗口（字体/字号/主题切换入口） | 3h |
| 字体/字号偏好持久化（编辑器侧） | 2h |
| 全局搜索（⌘⇧F） | 6h |
| Frontmatter / 标题结构小工具 | 2h |
| **小计** | **~13h** |

### 暂不做（除非真实用户持续提出）

- 模板系统
- HTML ↔ MD 双向转换
- Vim 模式 / Minimap / 打字机模式
- CSV/JSON 等多格式预览扩张

---

## 八、技术债清理路径

```
当前状态                         重构后
─────────                        ────────
AppState (状态 + 协调)      →     AppState (核心状态)
                                 + DocumentOpenCoordinator
                                 + PreviewCoordinator
                                 + SessionStore

Folder-first 入口            →     Doc-first 入口
(Open Folder 才像主流程)           + 单文件打开
                                 + 拖入文件即预览
                                 + 外部文档打开

HTML 内嵌 Swift              →     Resources/Preview/
(300 行字符串)                     ├─ template.html
                                 ├─ themes/
                                 │   ├─ github.css
                                 │   ├─ nord.css
                                 │   └─ dracula.css
                                 └─ scripts/
                                     └─ bridge.js

整页 reload 预览             →     保存触发的局部 innerHTML 更新
                                 + 滚动位置保留
                                 + 三套主题切换

无日志                       →     OSLog 统一封装
Xcode-only 测试              →     Xcode + CI + 命令行兼容测试策略
```

---

## 九、总体评价

**实际能用 6/10**，**方向潜力 8/10**。

- 架构底子是对的：`SwiftUI + NSTextView + WKWebView` 适合做原生本地预览器
- 当前最有价值的能力是"把 md/html **看对、看好**"，编辑只是顺手做的事
- 短板已不再是崩溃，而是**预览质量没跟上"预览优先"的定位**：内嵌模板难维护、整页 reload 闪烁、缺主题、缺导出
- 只要 Sprint 1 的"预览质量"把关做完，MEditor 就会从"能打开 md 的应用"跨到"愿意反复用的预览器"

**最关键的两件事**：

1. **抽离 HTML 模板** — 这是后面所有预览能力（主题、暗色、导出、修补）的底座
2. **减轻整页 reload** — 保存触发的局部更新足够好用，但不能闪到用户怀疑产品质量

这两步完成后，代码块复制、Outline、图片粘贴等编辑增强功能会有更稳的根。
反过来，如果继续优先做模板系统或 HTML ↔ MD 互转，项目会更快变复杂，但不会更快变好用。

---

## 附录：每个文件的角色与建议

| 文件 | 行数 | 关键作用 | 主要建议 |
|------|------|----------|----------|
| `MEditorApp.swift` | 138 | App 入口、菜单、命令 | 统一 `openFolder/openFile/外部文档打开` 语义 |
| `ContentView.swift` | 232 | 主布局（Sidebar/Editor/Preview） | 从 folder-first 调整为 doc-first 入口体验 |
| `AppState.swift` | 260 | 全局状态 | 拆分（见 §8），保留"保存触发预览刷新"语义但去掉整页 reload |
| `NativeEditorView.swift` | 187 | NSTextView 包装 | ✅ 已修循环。后续支持字体配置 |
| `MarkdownWebPreview.swift` | 442 | WKWebView 渲染 MD | ⚠️ 抽 HTML 模板 + 局部 innerHTML 刷新 + 主题切换（最高优先级） |
| `FileSidebar.swift` | 287 | 文件树 | 合并搜索/非搜索 List 重复 |
| `FileService.swift` | 65 | 文件 I/O | 后续区分"可显示"与"可编辑"文件类型 |
| `FileWatcherService.swift` | 60 | FSEvents 监听 | ✅ 已修类型错误。改 bundle ID |
| `HighlightService.swift` | 17 | 引擎注册 | 暂无 |
| `MarkdownHighlightEngine.swift` | 60 | MD regex 高亮 | 引入更细粒度规则 |
| `HTMLHighlightEngine.swift` | 60 | HTML regex 高亮 | 同上 |
| `Models/*` | 39 | FileItem / EditorTab | 暂无 |
| `Protocols/*` | 14 | 协议定义 | 暂无 |

---

## 附录：参考产品的差异分析

| 产品 | 优势 | MEditor 的差异 |
|------|------|---------------|
| **Typora** | 所见即所得编辑 | MEditor 是预览器+轻编辑，不追求 WYSIWYG |
| **iA Writer** | 极简专注写作 | MEditor 不主打写作，主打**看文档** |
| **Obsidian** | 双链、插件系统 | 目标用户不同，不学 |
| **VS Code** | 多文件 / Git / 扩展 | 体量太重，MEditor 走极简原生路线 |
| **MacDown** | 类 MEditor，已停更 | 借鉴 PDF 导出 |
| **Marked 2** | macOS 原生 Markdown 预览器 | **最直接对标** — 但 Marked 2 几乎不做编辑，MEditor 多了"修补型编辑"差异化 |

差异化建议：MEditor 应在 「**macOS 原生 + 极速启动 + 高质量预览 + 顺手修补**」 这条窄路上做到极致。这是 Electron 类编辑器（Typora、Obsidian）难以同样轻盈地做到的，也是纯预览器（Marked 2）覆盖不到的。
