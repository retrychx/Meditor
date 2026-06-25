# MEditor 三大演化方向深度分析

> 日期：2026-06-14 · 基于代码实际结构分析

---

## 方向一：AI 写作助手

### 1.1 现状与机会

当前代码结构已具备接入 AI 的所有基础：

- `JSBridge.swift` — Swift ↔ JS 双向通信，安全且完善
- `NativeEditorView.swift`（NSTextView）— 可拦截键盘事件、插入文本
- `MarkdownWebPreview.swift`（WKWebView）— 可在预览侧触发 AI 反馈
- `AppState` 的 Manager 架构 — 新增 `AIManager` 不破坏现有结构

### 1.2 三个实现层次

#### 层次一：零成本接入 — macOS Writing Tools（1-2周）

macOS 26 起，Apple 提供系统级 AI 写作工具（Writing Tools），`NSTextView` 默认就能获得：
- 润色（Proofread）
- 重写（Rewrite）
- 摘要（Summarize）
- 翻译（Translate）

**代价：几乎为零**。只要确认 `NativeEditorView` 里的 `NSTextView` 没有禁用系统菜单，这些能力就自动出现在右键菜单里。

这是**立即能做的事**，无需写任何 AI 逻辑。

```swift
// NativeEditorView.swift 确认没有这行即可
textView.isAutomaticTextReplacementEnabled = false  // ← 检查是否禁用了系统功能
```

#### 层次二：内嵌 AI 操作面板（2-4周）

在选中文本后，浮出一个轻量操作条（参考 Notion AI 的交互）：

```
选中文字后浮出：
┌────────────────────────────────────────┐
│  ✨ AI  [润色] [简化] [扩写] [翻译▾]  │
└────────────────────────────────────────┘
```

**架构设计：**
```
NativeEditorView（选中文本）
    ↓ 通知 AppState
AIManager（新增）
    ↓ 调用 API（可配置 Endpoint）
    ↓ 流式返回 token
NativeEditorView（实时替换选中内容）或 PreviewPanel（侧边对比）
```

**API 接入策略（可配置）：**
```swift
enum AIEndpoint {
    case appleWritingTools          // 系统内置，无需 Key
    case openAI(key: String)        // OpenAI API
    case custom(url: URL, key: String)  // 内网 LLM ← 最重要
}
```

设置页允许填入内网 LLM 地址，数据完全不出内网。这是面向企业用户的关键设计。

#### 层次三：工作区上下文感知 AI（4-8周）

这是 MEditor 独有的能力——其他 AI 工具不知道你的文件树。

```
用户在写文档时，AI 可以：
- 引用同目录其他文档的内容（"参考 README 里的架构说明"）
- 检测跨文件的术语一致性（"这里叫 UserID，另一篇叫 userId"）
- 自动生成文档间的交叉引用
- 基于 Git diff 生成变更说明
```

**实现依赖：**
- 需要先完成全局搜索的索引基础设施（`WorkspaceIndexService`）
- 在 AI 请求时注入相关文件片段作为上下文

### 1.3 风险与边界

| 风险 | 应对 |
|------|------|
| AI 响应慢影响编辑体验 | 所有 AI 调用异步，不阻塞编辑器 |
| 数据安全（外网 API）| 默认提示用户，内网 LLM 优先 |
| AI 改错内容 | 操作前保存快照，支持一键撤销 |
| 流式渲染乱序 | 用 Swift Concurrency `AsyncStream` 顺序消费 |

### 1.4 产品价值结论

> AI 不是 MEditor 的附加功能，是下一阶段的核心竞争力。
> 原生应用 + 本地文件上下文 + 内网 LLM = 其他工具复制不了的组合。

---

## 方向二：macOS 系统深度集成

### 2.1 现状

MEditor 是纯 Swift/SwiftUI + AppKit 的原生应用，具备做系统集成的所有条件，但目前几乎没有利用 macOS 系统级 API。这是最被低估的方向。

### 2.2 四个具体集成点

#### ① CoreSpotlight 文档索引（1周，高价值）

用户在 Finder 搜索框里直接搜 Markdown 文件内容，MEditor 的文档出现在搜索结果里，点击直接跳转。

```swift
// 新增 SpotlightIndexService.swift
import CoreSpotlight

final class SpotlightIndexService {
    
    func index(url: URL, content: String, title: String) {
        let item = CSSearchableItem(
            uniqueIdentifier: url.absoluteString,
            domainIdentifier: "com.meditor.documents",
            attributeSet: {
                let attrs = CSSearchableItemAttributeSet(contentType: .text)
                attrs.title = title
                attrs.contentDescription = String(content.prefix(500))
                attrs.textContent = content         // 全文索引
                attrs.contentURL = url
                attrs.thumbnailURL = nil            // 可加预览图
                return attrs
            }()
        )
        
        CSSearchableIndex.default().indexSearchableItems([item]) { error in
            // 错误静默处理，不影响主流程
        }
    }
    
    func deindex(url: URL) {
        CSSearchableIndex.default().deleteSearchableItems(
            withIdentifiers: [url.absoluteString]
        )
    }
}
```

**触发时机：**
- 文件保存时 → 更新索引
- 文件删除时 → 删除索引
- 工作区切换时 → 批量索引

集成点：在 `TabManager` 的保存回调里调用，对现有架构零侵入。

---

#### ② Quick Look 插件（1-2周，体验感知强）

在 Finder 里选中 `.md` 文件，按空格键，直接看到渲染后的 Markdown（而不是原始文本）。

```
Finder 空格预览 .md 文件 → 渲染好的 HTML 样式 ← MEditor Quick Look 扩展
```

**实现方式：** 新增一个 Quick Look Extension Target（`MEditorQLExtension`），复用现有的 HTML 渲染逻辑（marked.js + highlight.js）。

```swift
// QLPreviewingController.swift（扩展 Target）
import QuickLook

class PreviewViewController: NSViewController, QLPreviewingController {
    
    func preparePreviewOfFile(at url: URL) async throws {
        let content = try String(contentsOf: url, encoding: .utf8)
        // 复用 MEditor 的渲染 HTML 逻辑
        let html = MarkdownRenderer.render(content, theme: .github)
        webView.loadHTMLString(html, baseURL: url.deletingLastPathComponent())
    }
}
```

**价值评估：** 对用户感知极强。用户安装 MEditor 后，整个 macOS 的 Markdown 体验都改善了，不只是在 App 内部。这是口碑传播点。

---

#### ③ Shortcuts App 集成（1-2周，自动化场景）

让 MEditor 成为 macOS 自动化工作流的节点。

**设计的 AppIntents：**

```swift
// MEditorIntents.swift
import AppIntents

// 意图1：导出当前文档为 PDF
struct ExportToPDFIntent: AppIntent {
    static var title: LocalizedStringResource = "导出为 PDF"
    
    @Parameter(title: "文件路径")
    var filePath: String
    
    @Parameter(title: "输出目录")
    var outputPath: String
    
    func perform() async throws -> some IntentResult {
        // 调用 PreviewExporter 逻辑
        let url = URL(fileURLWithPath: filePath)
        let outputURL = try await PreviewExporter.exportPDF(from: url)
        return .result(value: outputURL.path)
    }
}

// 意图2：打开工作区
struct OpenWorkspaceIntent: AppIntent {
    static var title: LocalizedStringResource = "打开工作区"
    
    @Parameter(title: "目录路径")
    var directoryPath: String
    
    func perform() async throws -> some IntentResult {
        // 通知 App 打开指定目录
    }
}

// 意图3：批量转换 MD → HTML
struct BatchExportHTMLIntent: AppIntent { ... }
```

**典型使用场景：**
```
用户的 Shortcuts 自动化流程：
每周五 18:00 →
  1. MEditor: 导出 weekly-report.md 为 PDF
  2. Mail: 发送给团队
  3. MEditor: 清空周报模板
```

---

#### ④ Share Sheet 集成（0.5周，与 GitLab Snippet 联动）

系统级分享菜单里出现 MEditor 的分享选项，支持从其他应用把文本发送到 MEditor 新建文档。

```swift
// 注册为 Share Extension
// Info.plist 注册 NSExtension + NSExtensionActivationRule
// 支持接收 public.text / public.html

class ShareViewController: NSViewController {
    func didSelectPost() {
        // 把收到的文本在 MEditor 新建 Tab 并填入
    }
}
```

**反向价值：** Safari 里选中一段网页文字 → 分享到 MEditor → 自动转换为 Markdown 并新建文档。完美配合 HTML → MD 转换功能。

### 2.3 实施顺序建议

```
Week 1:  CoreSpotlight 索引（零感知接入，高价值）
Week 2:  Quick Look 插件（用户感知最强）
Week 3:  Shortcuts AppIntents（导出/打开工作区）
Week 4:  Share Sheet 扩展（配合 AI 和 GitLab 分享）
```

### 2.4 产品价值结论

> 系统集成不是"功能"，是"融入用户操作系统"的过程。
> 做好这四点，MEditor 就不只是一个应用，而是 macOS 文档体验的一部分。
> 这是 Electron 竞品的永久盲区。

---

## 方向三：企业文档流转集成

### 3.1 现状分析

**已有的基础设施（比想象的更成熟）：**

```
ShareManager.swift       ← 已有，协调分享流程
LocalShareServer.swift   ← 局域网分享，一次性 Token 鉴权
DocumentCommentStore.swift ← 批注系统，本地 UserDefaults 存储
```

`DocumentCommentStore` 目前纯本地：支持添加/删除/resolve 批注，但只存在分享者自己的电脑上，收到方看不到。**这是最大的未被激活的价值。**

### 3.2 三条流转链路

#### 链路一：GitLab Snippet 分享（已有技术方案）

参见 `docs/gitlab-snippet-share.zh.md`，这条链路最近，直接开发即可。

核心价值链：
```
编辑完成 → 一键上传 GitLab Snippet → 复制链接 → 同事浏览器打开
```

#### 链路二：批注云同步（DocumentCommentStore 升级）

当前批注存在 UserDefaults 里，无法跨设备/跨人。升级方案：

**Option A：GitLab Issue / MR 评论同步（推荐）**

Snippet 上传后，收到方在 GitLab 页面评论 → MEditor 定时拉取评论 → 显示在本地批注面板。

```swift
// GitLabService 新增方法
func fetchSnippetComments(snippetId: Int) async throws -> [SnippetComment]
func addSnippetComment(snippetId: Int, text: String) async throws

// DocumentCommentStore 升级
struct DocumentComment: Codable {
    let id: UUID
    var text: String
    var createdAt: Date
    var isResolved: Bool
    var author: String?      // 新增：评论者
    var gitLabNoteId: Int?   // 新增：对应 GitLab Note ID
    var source: CommentSource // local | gitlab
}
```

实现后的体验：
```
分享者（MEditor）→ 上传 Snippet → 链接给同事
同事（浏览器）→ 在 GitLab 页面评论
分享者（MEditor）→ 点击"刷新评论" → 本地批注面板出现同事的意见
分享者 → resolve 批注 → GitLab 上也标记 resolved
```

**Option B：更轻量 — 批注导出为 Markdown 附录**

不做网络同步，而是把批注列表渲染成文档底部的 `<!-- comments -->` 区域，导出 HTML 时一并带上。收到方可以看到，但不能实时互动。2天可以做完。

#### 链路三：内部平台发布适配器（V3 路线图，长期）

这是工作量最大的部分，建议放到前两条链路验证后再做。

**设计思路（发布适配器接口）：**

```swift
protocol DocumentPublisher {
    var name: String { get }           // "GitLab Snippet" / "内部文档平台" / "Confluence"
    var icon: String { get }
    
    func publish(
        title: String,
        content: String,
        options: PublishOptions
    ) async throws -> PublishResult    // 返回链接/ID
    
    func update(
        id: String,
        content: String
    ) async throws -> PublishResult
}

// 具体实现
class GitLabSnippetPublisher: DocumentPublisher { ... }
class InternalDocPublisher: DocumentPublisher { ... }         // 组织内部 内部文档平台
class ConfluencePublisher: DocumentPublisher { ... }
```

这个接口设计好了，增加新平台只要实现 Protocol，不改核心逻辑。

### 3.3 企业场景的核心洞察

**DocumentCommentStore 目前是孤立系统，接入 GitLab 后变成协作系统。**

这个变化的价值在于：**MEditor 从"个人工具"升级为"团队工具节点"**，使用场景从"我在用"变成"我们在用"。

对个人开发者来说，"我在用"就够了。但对于团队推广、产品留存来说，"我们在用"才是护城河——当多个人依赖同一个工具协作，迁移成本就出现了。

### 3.4 三条链路的优先级

```
立即做：GitLab Snippet 分享（2周，已有完整方案）
    ↓
短期做：批注 GitLab 同步 Option B（导出附录，2天）→ Option A（同步，1周）
    ↓
中期做：发布适配器接口设计 + GitLab 实现
    ↓
长期做：内部文档平台 / 其他平台适配器
```

---

## 综合：三个方向的协同关系

```
                    AI 写作助手
                         │
          ┌──────────────┼──────────────┐
          │              │              │
    理解工作区       改写/润色内容    生成发布摘要
    上下文           ↓               ↓
          │       文档内容更好    一键发布到 GitLab
          │
    macOS 系统集成                企业文档流转
          │                           │
    Spotlight 让文档可发现       GitLab 让协作可能
    Quick Look 降低查阅成本      批注同步让反馈闭环
    Shortcuts 接入工作流         发布适配器接入平台
```

三个方向不是并列竞争关系，而是**相互增强**：

- AI 改写后 → Spotlight 能搜到更好的内容
- Quick Look 发现文档 → 触发分享 → GitLab 评论 → AI 根据评论优化
- Shortcuts 自动化 → 定时导出 → 发布到平台

---

## 行动建议

| 优先 | 方向 | 具体行动 | 工时 |
|------|------|----------|------|
| 本周 | macOS 集成 | CoreSpotlight 索引接入 | 3-4天 |
| 本周 | 企业流转 | GitLab Snippet 开发 | 1周 |
| 下周 | macOS 集成 | Quick Look 插件 | 1周 |
| 下周 | AI | 确认 Writing Tools 在 NSTextView 是否已生效 | 1天 |
| 本月 | AI | 内嵌 AI 操作面板 MVP | 2-3周 |
| 下月 | 企业流转 | 批注 GitLab 同步 | 1周 |

---

*文档路径：`docs/three-directions-deep-analysis.zh.md`*
