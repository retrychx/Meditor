# MEditor AI Shell 可行性方案报告

> 版本：v1.0 · 日期：2026-06-15  
> 基于：MEditor 代码实际结构 + ai-assistant 现有能力
> 定性：**可行，推荐执行**

---

## 一、关键前提：已有 ai-assistant

在写方案之前，必须先解决一个战略判断：

**MEditor 要自己从零建 AI，还是复用 ai-assistant 已有的 AI 基础设施？**

### 1.1 ai-assistant 现有能力盘点

经过代码审查，ai-assistant 已经具备：

| 模块 | 文件 | 能力 |
|------|------|------|
| 意图分类 | `intent-classifier.ts` | 两级分类（规则 + LLM），6 种意图 |
| 工具注册 | `registry.ts` / `types.ts` | `ITool` 协议 + `ToolRegistry` 注册中心 |
| 工具执行 | `register.ts`（815行）| 50+ 工具已注册（文件/浏览器/外部/Agent）|
| 执行引擎 | `agent-loop.ts` / `dag-executor.ts` | 串行 + DAG 并行工作流 |
| 记忆系统 | `memory/` | 三层记忆 + 向量检索 |
| 快捷面板 | `QuickPanel.tsx` | `⌘+Shift+P` 浮动面板 + slash 命令 |
| 工具上下文 | `ToolContext` 接口 | cwd / workspaceRoot / signal / notify |

这意味着 MEditor 的 AI Shell 不需要从零实现 AI 引擎，而是：

> **给 ai-assistant 增加 MEditor 专用工具集，打通两个应用的 IPC 通信**

### 1.2 两种架构路径对比

#### 路径 A：MEditor 独立 AI Shell（自建）

```
MEditor 内嵌 Node.js sidecar → 复制 ai-assistant 的 AI 引擎 → 独立运行
```

| 优点 | 缺点 |
|------|------|
| 完全独立，不依赖 ai-assistant 运行 | 重复造轮子，维护两套 AI 引擎 |
| 可针对文档场景深度定制 | 工期 3-6 个月 |
| 无进程间通信复杂度 | 内存/CPU 占用翻倍 |

#### 路径 B：ai-assistant 扩展 MEditor 工具集（推荐）✅

```
ai-assistant（已运行）→ MEditor Tools → MEditor 暴露本地 HTTP API → 执行能力
```

| 优点 | 缺点 |
|------|------|
| 复用全部 AI 基础设施 | 需要 ai-assistant 同时运行 |
| 工期 2-4 周完成 MVP | MEditor 需要暴露内部 API |
| 工具共享（Spotlight、截图等已有）| 跨进程通信增加复杂度 |
| 记忆、工作流、DAG 全部直接用 | |

**结论：推荐路径 B。** ai-assistant 已经是完整的 AI 代理平台，MEditor 只需要成为它的一个"操作目标"。

---

## 二、整体架构设计

### 2.1 系统架构图

```
┌─────────────────────────────────────────────────────────────────┐
│                        用户                                      │
│                                                                  │
│   ① MEditor ⌘K         ② ai-assistant QuickPanel ⌘+Shift+P    │
│      命令面板                  自然语言输入                       │
└──────────┬──────────────────────────┬────────────────────────────┘
           │                          │
           ▼                          ▼
┌──────────────────┐      ┌───────────────────────────────────────┐
│  MEditor         │      │  ai-assistant (sidecar)               │
│  ──────────────  │      │  ─────────────────────────────────── │
│  CommandPalette  │◄────►│  IntentClassifier                     │
│  (⌘K 轻量版)     │  IPC │  ToolRegistry                         │
│                  │      │    ├─ MEditorTools (新增)             │
│  能力层(Swift)   │      │    ├─ FileSystemTools (已有)          │
│  ─────────────── │      │    ├─ BrowserTools (已有)             │
│  ExportCap       │◄────►│    └─ ExternalTools (已有)            │
│  ShareCap        │ HTTP │  AgentLoop / DAGExecutor              │
│  TemplateCap     │      │  MemorySystem                        │
│  DiagnosticsCap  │      └───────────────────────────────────────┘
│  GitLabCap       │
│  SpotlightCap    │
└──────────────────┘
```

### 2.2 通信协议：MEditor 暴露本地 HTTP API

MEditor 在 `LocalShareServer` 基础上，扩展一个仅限 localhost 的管理 API：

```
现有：局域网分享服务（端口 8899，公开）
新增：本地管理 API（端口 8900，仅 127.0.0.1）
```

```
GET  /api/v1/status              → 当前状态（打开的文件、工作区）
GET  /api/v1/workspace           → 工作区文件树
GET  /api/v1/file?path=...       → 读取文件内容
POST /api/v1/file                → 写入文件内容
POST /api/v1/export              → 触发导出（format: pdf/html/image）
POST /api/v1/share/gitlab        → 触发 GitLab Snippet 发布
POST /api/v1/template/apply      → 应用模板
POST /api/v1/comment             → 添加批注
GET  /api/v1/diagnostics         → 文档诊断结果
POST /api/v1/focus?path=...      → 切换到指定文件
```

**安全设计：**
- 只绑定 `127.0.0.1`，拒绝所有外网请求
- 请求需携带 Session Token（启动时生成，存入 Keychain）
- ai-assistant 作为可信客户端，首次配对时交换 Token

---

## 三、具体实现方案

### 3.1 MEditor 侧：能力 API 实现

#### 新增文件结构

```
Sources/MEditor/Services/
├── LocalAPIServer.swift         # 新增：本地管理 API（127.0.0.1:8900）
├── CapabilityExporter.swift     # 新增：能力到 HTTP 端点的映射
└── LocalShareServer.swift       # 已有（不变）
```

#### LocalAPIServer 核心实现

```swift
// LocalAPIServer.swift
// 复用 LocalShareServer 的 NWListener 模式，绑定 127.0.0.1

@MainActor
@Observable
final class LocalAPIServer {
    private(set) var isRunning = false
    private(set) var port: UInt16 = 8900
    private var sessionToken: String = ""
    
    // 注入 AppState，访问所有现有能力
    weak var appState: AppState?
    
    func start() {
        sessionToken = UUID().uuidString
        saveTokenToKeychain(sessionToken)
        // 启动 NWListener on 127.0.0.1:8900
    }
    
    // 路由处理
    func handle(method: String, path: String, body: Data?) async -> APIResponse {
        // 验证 Token
        guard isValidToken(from: request) else {
            return APIResponse(status: 401, body: ["error": "unauthorized"])
        }
        
        switch (method, path) {
        case ("GET", "/api/v1/status"):
            return handleStatus()
            
        case ("GET", "/api/v1/workspace"):
            return handleWorkspace()
            
        case ("POST", "/api/v1/export"):
            return await handleExport(body: body)
            
        case ("POST", "/api/v1/share/gitlab"):
            return await handleGitLabShare(body: body)
            
        // ... 其他路由
            
        default:
            return APIResponse(status: 404, body: ["error": "not found"])
        }
    }
    
    private func handleExport(body: Data?) async -> APIResponse {
        // 调用已有的 PreviewExporter
        guard let format = parseFormat(body),
              let exporter = appState?.previewExporter else {
            return APIResponse(status: 400, body: ["error": "invalid params"])
        }
        
        let result = try await exporter.exportHeadless(format: format)
        return APIResponse(status: 200, body: ["path": result.path])
    }
}
```

### 3.2 ai-assistant 侧：MEditor 工具集

在 `src-api/src/agent/tools/` 下新增 `meditor/` 目录：

```
tools/
├── meditor/
│   ├── client.ts           # MEditor API 客户端（HTTP 封装）
│   ├── tools.ts            # 工具定义（ITool 实现）
│   └── index.ts            # 导出
```

#### MEditor 工具定义

```typescript
// tools/meditor/tools.ts

import type { ITool, ToolContext, ToolResult } from '../types'
import { MEditorClient } from './client'

const client = new MEditorClient('http://127.0.0.1:8900')

// ── 工具1：读取当前文档 ───────────────────────────────────────────────────────

export const meditorGetCurrentFile: ITool = {
  name: 'meditor_get_current_file',
  description: '获取 MEditor 当前打开的文档内容和路径',
  schema: {
    type: 'object',
    properties: {},
    required: [],
  },
  metadata: { retryable: true, timeoutMs: 5000, category: 'external' },
  async execute(_args, _ctx): Promise<ToolResult> {
    const status = await client.getStatus()
    if (!status.currentFile) {
      return { success: false, error: 'MEditor 当前没有打开的文档' }
    }
    const content = await client.readFile(status.currentFile)
    return {
      success: true,
      data: { path: status.currentFile, content }
    }
  }
}

// ── 工具2：导出文档 ───────────────────────────────────────────────────────────

export const meditorExport: ITool = {
  name: 'meditor_export',
  description: '将 MEditor 当前文档导出为指定格式（pdf / html / image）',
  schema: {
    type: 'object',
    properties: {
      format: {
        type: 'string',
        enum: ['pdf', 'html', 'image'],
        description: '导出格式'
      },
      outputPath: {
        type: 'string',
        description: '输出路径（可选，默认桌面）'
      }
    },
    required: ['format'],
  },
  metadata: { retryable: false, timeoutMs: 30000, category: 'external' },
  async execute(args: any, _ctx): Promise<ToolResult> {
    const result = await client.export(args.format, args.outputPath)
    return { success: true, data: { outputPath: result.path } }
  }
}

// ── 工具3：发布到 GitLab ─────────────────────────────────────────────────────

export const meditorPublishGitLab: ITool = {
  name: 'meditor_publish_gitlab',
  description: '将 MEditor 当前文档发布到 GitLab Snippet，返回分享链接',
  schema: {
    type: 'object',
    properties: {
      title: { type: 'string', description: '标题（默认文件名）' },
      visibility: {
        type: 'string',
        enum: ['internal', 'private'],
        description: '可见性（默认 internal）'
      }
    },
    required: [],
  },
  metadata: { retryable: false, timeoutMs: 15000, category: 'external' },
  async execute(args: any, _ctx): Promise<ToolResult> {
    const result = await client.publishGitLab(args)
    return { success: true, data: { url: result.url } }
  }
}

// ── 工具4：写入/修改文档 ─────────────────────────────────────────────────────

export const meditorWriteFile: ITool = {
  name: 'meditor_write_file',
  description: '修改 MEditor 当前文档内容（AI 改写、润色后回写）',
  schema: {
    type: 'object',
    properties: {
      content: { type: 'string', description: '新的文档内容' },
      mode: {
        type: 'string',
        enum: ['replace', 'append', 'prepend'],
        description: '写入模式（默认 replace）'
      }
    },
    required: ['content'],
  },
  metadata: { retryable: false, category: 'external' },
  async execute(args: any, _ctx): Promise<ToolResult> {
    await client.writeFile(args.content, args.mode ?? 'replace')
    return { success: true, data: { message: '文档已更新' } }
  }
}

// ── 工具5：文档诊断 ───────────────────────────────────────────────────────────

export const meditorDiagnose: ITool = {
  name: 'meditor_diagnose',
  description: '对 MEditor 当前文档执行质量诊断，返回问题列表',
  schema: { type: 'object', properties: {}, required: [] },
  metadata: { retryable: true, category: 'external' },
  async execute(_args, _ctx): Promise<ToolResult> {
    const issues = await client.getDiagnostics()
    return { success: true, data: { issues, count: issues.length } }
  }
}

// ── 工具6：应用模板 ───────────────────────────────────────────────────────────

export const meditorApplyTemplate: ITool = {
  name: 'meditor_apply_template',
  description: '在 MEditor 工作区中基于指定模板创建新文档',
  schema: {
    type: 'object',
    properties: {
      templateName: { type: 'string', description: '模板名称' },
      outputPath: { type: 'string', description: '新文件路径' }
    },
    required: ['templateName'],
  },
  metadata: { retryable: false, category: 'external' },
  async execute(args: any, _ctx): Promise<ToolResult> {
    const result = await client.applyTemplate(args.templateName, args.outputPath)
    return { success: true, data: { path: result.path } }
  }
}

export const MEDITOR_TOOLS = [
  meditorGetCurrentFile,
  meditorExport,
  meditorPublishGitLab,
  meditorWriteFile,
  meditorDiagnose,
  meditorApplyTemplate,
]
```

#### 注册到 ai-assistant

```typescript
// register.ts 末尾新增
import { MEDITOR_TOOLS } from './meditor/index'

// MEditor 工具（仅在 MEditor 运行时注册）
async function registerMEditorTools() {
  const isRunning = await checkMEditorRunning()
  if (isRunning) {
    MEDITOR_TOOLS.forEach(tool => defaultRegistry.register(tool))
    console.log(`[tools] MEditor 工具集已注册（${MEDITOR_TOOLS.length} 个工具）`)
  }
}
registerMEditorTools()  // 启动时检测
```

### 3.3 使用场景示例

#### 场景一：通过 ai-assistant QuickPanel 操作 MEditor

```
用户在 QuickPanel 输入：
"帮我润色一下 MEditor 里正在编辑的文档，然后发布到 GitLab 给团队"

ai-assistant 执行：
  Step 1: meditor_get_current_file → 读取文档内容
  Step 2: [LLM 润色文档内容]
  Step 3: meditor_write_file(content=润色结果) → 回写到 MEditor
  Step 4: meditor_publish_gitlab(visibility="internal") → 发布
  Step 5: 返回 GitLab 链接，notify 用户
```

#### 场景二：MEditor ⌘K 面板（轻量版）

MEditor 自己实现一个轻量级命令面板，不依赖 ai-assistant：

```
⌘K → 输入"发布到 GitLab"
   → 匹配预定义 Slash 命令
   → 直接调用 GitLabService
   → 显示结果
```

两个入口并存：**⌘K 处理文档专属快捷操作，QuickPanel 处理需要 AI 推理的复杂意图。**

---

## 四、实施计划

### 4.1 分阶段里程碑

#### Phase 1：基础互通（2周）

**目标：** ai-assistant 能读写 MEditor 文件，基础工具跑通

**MEditor 侧（Swift）：**
- [ ] `LocalAPIServer.swift` — `/status` `/file` 读写端点
- [ ] Token 鉴权（Keychain 存储）
- [ ] 与 `AppState` 集成（不改现有 Manager 结构）

**ai-assistant 侧（TypeScript）：**
- [ ] `tools/meditor/client.ts` — HTTP 客户端
- [ ] `meditor_get_current_file` + `meditor_write_file` 两个工具
- [ ] 启动时检测 MEditor 并注册工具

**验收：**
```
QuickPanel: "帮我总结一下 MEditor 打开的文档"
→ ai-assistant 读取文档 → LLM 总结 → 返回结果 ✅
```

#### Phase 2：核心能力接入（2周）

**目标：** 导出、GitLab 发布、模板能力全部打通

**MEditor 侧：**
- [ ] `/export` — 调用 `PreviewExporter`（headless 模式）
- [ ] `/share/gitlab` — 调用新的 `GitLabService`
- [ ] `/template/apply` — 调用 `TemplateManager`
- [ ] `/diagnostics` — 文档诊断实现

**ai-assistant 侧：**
- [ ] `meditor_export` + `meditor_publish_gitlab` + `meditor_apply_template` + `meditor_diagnose`
- [ ] 工具注册完整（6个工具全部上线）

**验收：**
```
QuickPanel: "把当前文档导出 PDF 然后发给 GitLab"
→ 导出 PDF + 发布 Snippet + 返回链接 ✅
```

#### Phase 3：MEditor ⌘K 面板（2周）

**目标：** MEditor 内置轻量命令面板，不需要切换到 ai-assistant

**MEditor 侧（SwiftUI）：**
- [ ] `CommandPaletteView.swift` — ⌘K 触发，支持模糊搜索
- [ ] 预定义命令：导出/发布/模板/诊断/AI润色
- [ ] 执行进度展示（动画 + 结果气泡）
- [ ] AI润色 — 发送选中文本到 ai-assistant，结果回写

**验收：**
```
MEditor ⌘K → 输入"发布" → 选择"发布到 GitLab" → 执行成功 ✅
MEditor ⌘K → 输入"润色" → AI 改写当前文档 ✅
```

#### Phase 4：上下文感知（1个月）

**目标：** AI 感知工作区，主动建议，Spotlight 集成

- [ ] Spotlight 索引（文档保存时自动更新）
- [ ] Quick Look 插件（Finder 空格预览）
- [ ] 工作区上下文注入（ai-assistant 拉取文件树作为上下文）
- [ ] 使用习惯学习 + 主动建议

---

## 五、可行性评估

### 5.1 技术可行性

| 模块 | 可行性 | 关键依赖 | 风险 |
|------|--------|----------|------|
| LocalAPIServer（Swift NWListener） | ✅ 高 | 已有 LocalShareServer 示范 | 低 |
| IPC Token 鉴权 | ✅ 高 | macOS Keychain API | 低 |
| ai-assistant 工具扩展 | ✅ 高 | `ITool` 接口标准，直接实现 | 低 |
| PreviewExporter headless | ⚠️ 中 | WKWebView 无头导出需测试 | 中 |
| GitLab API 集成 | ✅ 高 | 标准 REST，Swift URLSession | 低 |
| ⌘K 命令面板 UI | ✅ 高 | 纯 SwiftUI Sheet | 低 |
| Spotlight 索引 | ✅ 高 | CoreSpotlight API 成熟 | 低 |
| Quick Look 插件 | ⚠️ 中 | 需独立 Extension Target | 中 |
| ai-assistant 工作区感知 | ✅ 高 | 拉取文件树 JSON 即可 | 低 |

### 5.2 工时评估

| Phase | 工时（含测试） |
|-------|---------------|
| Phase 1：基础互通 | 2周（40h）|
| Phase 2：核心能力 | 2周（40h）|
| Phase 3：⌘K 面板 | 2周（40h）|
| Phase 4：上下文感知 | 4周（80h）|
| **合计 MVP（Phase 1-3）** | **6周 · 120h** |
| **合计完整版（Phase 1-4）** | **10周 · 200h** |

### 5.3 依赖条件

| 条件 | 状态 | 备注 |
|------|------|------|
| ai-assistant 同时运行 | 需要 | Phase 1-2 依赖，Phase 3 后可独立 |
| MEditor 暴露本地 API | 需新开发 | Phase 1 的核心工作 |
| GitLab 内网可访问 | 需确认 | 通常满足 |
| 公司内网 LLM 接入 | 需确认 | ai-assistant 已配置则直接复用 |

---

## 六、风险与应对

### 风险一：两个 App 需要同时运行

**场景：** 用户只打开了 MEditor，没有运行 ai-assistant

**应对：**
- Phase 3 的 ⌘K 面板不依赖 ai-assistant（处理本地快捷命令）
- 检测到 ai-assistant 未运行时，AI 相关功能降级（灰显 + 提示）
- 长期：Phase 1-2 的能力迁移到 MEditor 内置 sidecar（可选路径）

### 风险二：LocalAPIServer 暴露本地攻击面

**应对：**
```swift
// 严格绑定 127.0.0.1
NWEndpoint.Host.ipv4(IPv4Address("127.0.0.1")!)

// Token 验证（启动时随机生成）
guard request.headers["X-MEditor-Token"] == sessionToken else {
    return 401
}

// 接口最小化原则（只暴露需要的端点）
```

### 风险三：ai-assistant 工具调用 MEditor 失败

**场景：** MEditor API 超时、文件锁定、格式错误

**应对：**
- 所有 MEditor 工具都有明确的 `timeoutMs`
- 失败返回 `{ success: false, error: "..." }` 标准格式
- ai-assistant 的 `smart-retry.ts` 自动处理重试

### 风险四：PreviewExporter headless 导出

**场景：** 导出 PDF 需要 WKWebView 完全渲染，headless 模式可能有差异

**应对：**
- 先用显示模式（弹出存储面板）作为降级
- 研究 `WKWebView` 离屏渲染方案（macOS 14+ 支持）

---

## 七、成功指标

### MVP（Phase 1-3 完成）

| 指标 | 目标值 |
|------|--------|
| 从自然语言到 MEditor 操作完成 | < 5秒（不含 LLM 响应时间）|
| ⌘K 命令面板搜索响应 | < 100ms |
| AI 操作成功率 | > 95% |
| MEditor API 请求延迟 | < 200ms（本地 HTTP）|

### 完整版（Phase 4 完成）

| 指标 | 目标值 |
|------|--------|
| Spotlight 搜索覆盖率 | 工作区内所有 .md 文件 100% |
| 上下文感知建议准确率 | > 80%（用户采纳率）|
| 工作区感知延迟 | 文件保存后 < 1秒更新索引 |

---

## 八、结论

**方案可行，推荐执行。**

核心判断：
1. **不重复造轮子** — ai-assistant 已有完整 AI 引擎，MEditor 扩展工具集即可
2. **渐进式** — Phase 1-2 先打通管道，Phase 3 做 UX，Phase 4 做智能化
3. **可降级** — ⌘K 面板不依赖 ai-assistant，核心文档功能不受影响
4. **安全** — 本地 IPC 绑定 127.0.0.1 + Token 鉴权，不增加攻击面
5. **工期合理** — MVP 6周，完整版 10周，节奏可控

**最小切入点（本周可以开始）：**
在 ai-assistant 的 `register.ts` 里写一个最简版 `meditor_get_current_file` 工具，MEditor 侧先做一个只有 `/status` 和 `/file` 的最小 LocalAPIServer。跑通这条管道，其余都是在这个基础上的扩展。

---

*文档路径：`docs/ai-shell-feasibility-report.zh.md`*
