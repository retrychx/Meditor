# MEditor 作为 AI Native Shell 的深度架构分析

> 日期：2026-06-15 · 性质：战略方向 + 技术架构推演

---

## 一、核心命题

**MEditor 的终局不是"功能更多的编辑器"，而是"文档领域的原生 AI Shell"。**

这意味着一次根本性的产品哲学转变：

```
旧哲学：开发者预判需求 → 写死功能 → 用户适应软件
新哲学：用户描述意图 → AI 理解编排 → Shell 执行能力
```

Shell 提供的是**能力（Capability）**，不是**功能（Feature）**。
AI 提供的是**编排（Orchestration）**，不是**逻辑（Logic）**。

---

## 二、什么是"能力"而不是"功能"

### 2.1 功能 vs 能力的区别

| | 功能（Feature） | 能力（Capability） |
|--|--|--|
| 定义方 | 开发者 | 开发者定义，AI 调用 |
| 触发方 | 用户点击按钮 | AI 理解意图后调用 |
| 组合性 | 固定流程 | 任意组合 |
| 可发现性 | 需要学习菜单 | 自然语言描述 |
| 例子 | "导出 PDF 按钮" | ExportCapability(format: .pdf) |

### 2.2 MEditor 现有能力盘点

MEditor 当前已有的原子能力（只是还没暴露给 AI）：

```swift
// 文件操作类
ReadFileCapability       // 读取文件内容
WriteFileCapability      // 写入/修改文件
CreateFileCapability     // 新建文件（从模板）
DeleteFileCapability     // 删除文件

// 内容转换类
RenderMarkdownCapability // MD → HTML 渲染
ExportPDFCapability      // 导出 PDF（PreviewExporter 已有）
ExportHTMLCapability     // 导出 HTML
ExportImageCapability    // 导出图片（2x PNG）

// 协作类
LANShareCapability       // 局域网分享（LocalShareServer 已有）
CommentCapability        // 添加/解决批注（DocumentCommentStore 已有）

// 工作区类
SearchWorkspaceCapability    // 全局搜索（待实现）
OpenFileCapability           // 打开/跳转文件
IndexSpotlightCapability     // Spotlight 索引（待实现）
```

**待添加的高价值能力：**
```swift
GitLabPublishCapability      // 发布到 GitLab Snippet
AITransformCapability        // AI 文本变换（润色/翻译/改写）
TemplateApplyCapability      // 应用模板
DiagnosticsCapability        // 文档诊断
```

### 2.3 能力的接口设计

```swift
// 统一能力协议
protocol MEditorCapability: Sendable {
    /// AI 用来理解这个能力做什么的描述
    static var description: CapabilityDescription { get }
    
    /// 执行能力
    func execute(
        context: DocumentContext,
        params: CapabilityParams
    ) async throws -> CapabilityResult
}

struct CapabilityDescription {
    let name: String           // "export_pdf"
    let humanName: String      // "导出为 PDF"
    let what: String           // "将当前文档导出为 PDF 文件"
    let when: String           // "用户需要分享或打印文档时"
    let params: [ParamSpec]    // 参数说明
    let output: OutputSpec     // 返回值说明
}

// DocumentContext：AI 编排时的上下文
struct DocumentContext {
    let currentFile: URL?
    let workspaceRoot: URL?
    let selectedText: String?
    let allOpenTabs: [EditorTab]
    let recentFiles: [URL]
}
```

---

## 三、AI 编排层的架构

### 3.1 整体架构图

```
用户意图（自然语言）
        │
        ▼
┌───────────────────────┐
│   Intent Classifier   │  ← 理解用户想做什么
│   意图分类器           │
└───────────┬───────────┘
            │
            ▼
┌───────────────────────┐
│   Capability Planner  │  ← 规划需要调用哪些能力、以什么顺序
│   能力规划器           │
└───────────┬───────────┘
            │
            ▼
┌───────────────────────┐
│   Capability Registry │  ← 所有已注册能力的目录
│   能力注册表           │
└───────────┬───────────┘
            │
      ┌─────┴──────┐
      ▼            ▼
ExportCap    GitLabCap  ...  ← 原子能力执行
      │            │
      └─────┬──────┘
            ▼
┌───────────────────────┐
│   Result Presenter    │  ← 把执行结果呈现给用户
│   结果呈现器           │
└───────────────────────┘
```

### 3.2 Intent Classifier（意图分类器）

不是简单的关键词匹配，而是 LLM 驱动的语义理解：

```swift
actor IntentClassifier {
    
    func classify(
        input: String,
        context: DocumentContext
    ) async throws -> ClassifiedIntent {
        
        // 构建系统提示：告诉 LLM 有哪些能力
        let systemPrompt = CapabilityRegistry.shared.buildSystemPrompt()
        
        // 构建用户上下文
        let contextPrompt = """
        当前打开的文件：\(context.currentFile?.lastPathComponent ?? "无")
        工作区：\(context.workspaceRoot?.path ?? "无")
        选中文字：\(context.selectedText ?? "无")
        """
        
        // LLM 返回结构化的执行计划
        let response = try await llm.complete(
            system: systemPrompt,
            user: "\(contextPrompt)\n\n用户意图：\(input)",
            responseFormat: .json(IntentPlan.self)
        )
        
        return response.intent
    }
}

struct IntentPlan: Codable {
    let understanding: String           // AI 的理解："用户想把当前文档发布给团队"
    let steps: [CapabilityInvocation]  // 执行步骤
    let clarificationNeeded: String?   // 如果有歧义，需要追问什么
}

struct CapabilityInvocation: Codable {
    let capability: String             // "export_pdf"
    let params: [String: AnyCodable]  // 参数
    let dependsOn: [Int]?             // 依赖哪些前置步骤的输出
}
```

### 3.3 执行示例

**用户输入：** "把这篇文档整理成 PDF 发给 GitLab 上的团队"

**AI 规划的执行步骤：**
```json
{
  "understanding": "用户想将当前文档导出为 PDF，并上传到 GitLab 分享",
  "steps": [
    {
      "step": 1,
      "capability": "export_pdf",
      "params": { "source": "current_file" },
      "output": "pdf_path"
    },
    {
      "step": 2,
      "capability": "gitlab_publish",
      "params": {
        "content": "{{step1.markdown_content}}",
        "title": "{{current_file.name}}",
        "visibility": "internal"
      },
      "dependsOn": [1]
    },
    {
      "step": 3,
      "capability": "copy_to_clipboard",
      "params": { "text": "{{step2.url}}" }
    }
  ]
}
```

**执行结果展示：**
```
✅ 已完成
  ① 导出 PDF → weekly-report.pdf
  ② 发布到 GitLab → https://gitlab.xxx.com/-/snippets/123
  ③ 链接已复制到剪贴板
```

---

## 四、用户交互层：AI Command Center

### 4.1 入口设计

**⌘K 命令面板**（核心入口，所有 AI 功能的统一入口）：

```
┌─────────────────────────────────────────────────────┐
│  🔍  描述你想做什么...                               │
├─────────────────────────────────────────────────────┤
│  最近使用                                            │
│  ✨ 导出当前文档为 PDF                               │
│  ✨ 润色选中文字                                     │
│  ✨ 发布到 GitLab                                    │
├─────────────────────────────────────────────────────┤
│  建议操作（基于当前上下文）                           │
│  💡 该文档上次修改是 3 天前，要导出最新版本吗？       │
│  💡 检测到未 resolve 的批注，要整理后再分享吗？       │
└─────────────────────────────────────────────────────┘
```

用户可以：
- 输入自然语言："帮我把这周所有修改过的文档打包导出"
- 选择快捷操作
- 接受 AI 的主动建议

### 4.2 "一次性功能"的实现：临时 Workflow

这是你提到的"一次性"的具体落地形式。

用户输入一个复杂需求：
> "扫描工作区里所有 README，提取每个项目的技术栈，生成一个汇总表格保存到 summary.md"

这个需求没有对应的按钮，但 AI 可以：
1. 枚举工作区所有 README 文件（`SearchWorkspaceCapability`）
2. 逐个读取内容（`ReadFileCapability` × N）
3. 提取技术栈信息（`AITransformCapability`）
4. 生成 Markdown 表格（内联生成）
5. 写入 summary.md（`WriteFileCapability`）

这个"功能"从未被开发者写过，但 AI 通过组合现有能力完成了它。**这就是"一次性功能"的本质**：不是软件有这个功能，而是这个任务被即时完成了。

### 4.3 自我定制化：偏好学习

```swift
// 用户行为观察器
actor UsageObserver {
    
    // 记录用户的操作模式
    func record(action: UserAction, context: DocumentContext) {
        // 例：用户每次保存后都手动导出 PDF
        // → 建议："是否要在保存时自动导出 PDF？"
    }
    
    // 生成个性化建议
    func generatePersonalizedSuggestions() -> [Suggestion] {
        // 分析历史 → 提炼规律 → 推荐自动化
    }
}
```

用户不需要去设置页找选项，AI 主动问："我注意到你每次修改这类文档后都会发到 GitLab，要帮你设置自动化吗？"

---

## 五、"Shell"的价值：为什么这不能是 Web App

这是整个方案的核心逻辑，也是 MEditor 作为原生应用的最终价值所在。

### 5.1 原生 Shell 提供的不可替代能力

```
┌─────────────────────────────────────────────────────────┐
│                   AI 能做的事                            │
│  理解意图 / 生成内容 / 规划步骤 / 转换格式               │
├─────────────────────────────────────────────────────────┤
│              AI 做不到、Shell 必须提供的                  │
│                                                          │
│  🔐 沙盒文件权限     访问 ~/Documents 不需要用户手动选   │
│  🔑 系统 Keychain   安全存储 GitLab Token / API Key     │
│  🖥 原生渲染         NSTextView 的实时高亮、性能          │
│  📱 系统集成         Spotlight / Quick Look / Shortcuts  │
│  🏃 本地执行         AI 生成的操作在本机执行，数据不出境  │
│  🔒 可信边界         用户授权过的 App，AI 在授权范围内操作│
└─────────────────────────────────────────────────────────┘
```

**关键点：AI 需要一个可信的执行环境。**

如果 AI 能随意读写文件、调用网络，那就是安全噩梦。Shell 的价值正是**提供一个边界清晰的执行沙盒**：AI 只能调用已注册的 Capability，每个 Capability 只有明确的权限范围。

### 5.2 与 Web App 的根本差异

| | Web App + AI | 原生 Shell + AI |
|--|--|--|
| 文件访问 | 用户手动上传 | 直接访问本地文件树 |
| 数据安全 | 内容上传到云端 | 本地 LLM，数据不出机器 |
| 系统集成 | 无 | Spotlight/Quick Look/Shortcuts |
| 执行性能 | 网络延迟 | 本地即时执行 |
| 权限模型 | 宽泛（整个浏览器） | 精确（App 沙盒） |
| 可信度 | 低（JS 可随意执行）| 高（系统签名 + 沙盒）|

---

## 六、产品形态演进路径

### 阶段一：能力化重构（当前 → 3个月）

**目标：** 把现有功能改造成可被 AI 调用的原子 Capability

```
不改变用户体验，只是在底层建立 Capability 注册体系。
现有的导出/分享/模板/批注，全部包装为标准 Capability 接口。
```

**里程碑：**
- [ ] CapabilityRegistry 基础设施
- [ ] 现有功能全部注册（导出/分享/模板/搜索/批注）
- [ ] GitLab Publish Capability（新增）
- [ ] AI Transform Capability（新增，调用 LLM API）

### 阶段二：AI Command Center MVP（3 → 6个月）

**目标：** ⌘K 命令面板上线，支持自然语言触发已有 Capability

```
用户通过自然语言描述意图 → AI 规划执行步骤 → 调用 Capability → 展示结果
```

**里程碑：**
- [ ] ⌘K 命令面板 UI
- [ ] IntentClassifier（接入内网 LLM）
- [ ] 串行 Capability 执行引擎
- [ ] 执行过程的进度展示和错误处理

### 阶段三：上下文感知与个性化（6 → 12个月）

**目标：** AI 感知整个工作区，主动建议，学习用户习惯

```
AI 知道你的文件树、最近操作、常用模式
→ 主动建议而不是等待触发
→ 识别重复操作并推荐自动化
```

**里程碑：**
- [ ] WorkspaceContext Service（索引整个工作区）
- [ ] 使用模式学习与建议引擎
- [ ] 自动化 Workflow 创建与管理
- [ ] Spotlight / Shortcuts 集成（让 AI 的自动化能跨应用执行）

---

## 七、风险与应对

### 风险一：AI 误解意图导致破坏性操作

**场景：** 用户说"清理一下"，AI 误删了文件

**应对：**
```swift
// 危险操作分级
enum CapabilityRiskLevel {
    case safe       // 读取、渲染、复制 → 直接执行
    case moderate   // 导出、发布 → 执行前简要确认
    case dangerous  // 删除、覆盖 → 强制确认 + 预览差异
}

// 所有 dangerous 级操作执行前显示：
// "⚠️ AI 即将删除 3 个文件，确认执行？[查看详情] [取消] [确认]"
```

### 风险二：LLM 响应慢影响操作流畅性

**应对：**
- 意图分类轻量化（本地小模型做初步分类，复杂意图再走大模型）
- 执行步骤流式展示（不等全部规划完才开始）
- 纯命令匹配（高频操作不走 LLM，直接匹配关键词）

### 风险三：能力组合出现意外副作用

**应对：**
- Capability 执行前记录快照（类似 Time Machine）
- 支持整个 Workflow 一键 Undo
- Capability 必须声明副作用范围（只写当前文件 / 可能修改多文件 / 涉及网络）

### 风险四：用户不知道能说什么

**应对：**
- ⌘K 面板提供基于上下文的建议（不是空白输入框）
- 逐步引导：先让用户用预设指令，再引导自然语言
- 使用历史：显示"其他人常用的操作"

---

## 八、竞争格局与差异化

### 8.1 当前竞品没有做到的

| 竞品 | 问题 |
|------|------|
| Notion AI | 云端，数据出境；重型平台，非本地工作流 |
| Obsidian + AI 插件 | 插件质量参差，没有统一的 Capability 模型 |
| Typora | 无 AI，单文件，无工作区概念 |
| VS Code + Copilot | 面向代码，不面向文档交付流程 |
| Bear | 轻量但封闭，无法接入企业系统 |

### 8.2 MEditor 的差异化护城河

```
原生 macOS 性能
    +
本地文件全权访问
    +
企业内网 LLM（数据不出内网）
    +
GitLab / 企业系统集成
    +
统一 Capability 执行模型
    =
"企业技术人员的本地文档 AI 工作台"
```

这个组合，没有任何现有产品能完整提供。

---

## 九、一句话总结

> MEditor 的演化终点不是"更好的 Markdown 编辑器"，
> 而是**"一个懂文档工作流的本地 AI 执行环境"**。
>
> 功能由 AI 按需生成，能力由 Shell 提供，数据留在本地，权限由系统保障。
> 用户不需要学习软件，软件学习用户。

---

## 附：下一步最小可行行动

1. **本周**：设计 `MEditorCapability` 协议 + `CapabilityRegistry`（纸面设计，不写代码）
2. **下周**：把 `PreviewExporter`、`LocalShareServer`、`TemplateManager` 包装为 Capability
3. **第3周**：⌘K 命令面板 UI（先做快捷命令，不做 LLM 解析）
4. **第4周**：接入 LLM，实现最简单的意图 → 单步 Capability 执行

**从"命令面板"开始，比从"AI 对话框"开始更容易被接受，用户学习成本低。**

---

*文档路径：`docs/ai-shell-architecture-analysis.zh.md`*
