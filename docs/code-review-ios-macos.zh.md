# MEditor 客户端代码评审：iOS 与 macOS 双端四视角

- **日期**：2026-08-08
- **范围**：`Mobile/`（iOS 客户端，25 个源文件，约 2.7k 行）与 `Sources/MEditor/`（macOS 客户端，160+ 文件，约 33.5k 行）
- **评审视角**：产品专家 / 编辑器设计专家 / UI 设计专家 / Agent 设计专家
- **证据约定**：所有结论附 `文件:行号`，可溯源。

---

## 一、总评

**架构与品味远超一般独立开发者的水平，问题不在"代码烂"，而在两端的定位与成熟度落差。**

- **iOS 端**：架构清晰、设计系统出色，但它是 macOS 桌面心智的"薄壳移植"——缺文件浏览、AI 与文档两张皮、编辑器是纯源码无高亮。它需要的是**为移动场景重新设计工作流**，而不是补功能。
- **macOS 端**：是"真产品"，几个区域做了教科书级工程（Agent 命令安全、编辑器性能、编辑↔预览联动），但背着**功能膨胀 + 安全债 + undo/会话健壮性**三个包袱。

最有价值的跨端发现：**两端在"AI 写回 vs undo 栈"和"大文档全文内联进 prompt"两个问题上独立犯了同样的错**——这说明不是平台 bug，而是产品层对"AI 改动如何安全落地"缺统一设计。

---

## 二、iOS 客户端评测

### 2.1 产品专家视角

**亮点**
- 信息架构克制：两个一级页面（文档/设置），文档页编辑/预览切换，AI 浮层。没有硬塞桌面端的标签页/文件树。
- 移动端文件体验扎实：Quick Action、微信"用其他应用打开"（`.onOpenURL` → `store.openIncoming`）、iCloud 原地打开 + security-scoped bookmark 持久化（`DocumentStore.swift:78-100`）。

**关键问题**

| 级别 | 问题 | 证据 |
|---|---|---|
| P1 | **iOS 没有目录浏览**。数据源只有最近列表，裁剪到 50 条。macOS 有完整文件树，手机退化成"最近 + 系统选择器"。 | `DocumentHomeView.swift:42`、`RecentHistory.swift:212` |
| P2 | **AI 默认关闭**。provider 默认 `.disabled`，首启不配 API Key 就没有 AI，激活漏斗难看。 | `MobileAISettings.swift:42` |
| P3 | **AI 与文档两张皮**。完整闭环（选中→AI 优化→替换）拆散在三处，最难发现的入口是长按编辑菜单。 | `MarkdownTextEditor.swift:15`、`MarkdownPreviewView.swift:45-69`、`AIChatView.swift:177-218` |
| P4 | **agent 能静默切换当前文档**，无用户确认。 | `MobileAgentContext.swift:124-127` |

### 2.2 编辑器设计专家视角

**亮点**
- `MarkdownTextEditor` 封装有功底：inputAccessoryView 工具条、行级规则再点一次去除、`setStyledText` 保光标与滚动（`MarkdownTextEditor.swift:104-114`）、关闭智能引号保护 Markdown 符号。
- 所有写入收敛到 `DocumentStore.applyManualEdit` + 防抖自动保存（`DocumentStore.swift:389`）。

**关键问题**

| 级别 | 问题 | 证据 |
|---|---|---|
| E1 | **撤销栈在 AI 写入后被清掉**。AI 写回 store.text → `updateUIView` 整段重挂 attributedText，UIKit 原生 undo 栈连根清掉，"摇一摇撤销"在 AI 改动后失效。 | `MarkdownTextEditor.swift:104-114` |
| E2 | **源码编辑无语法高亮**。macOS 主打 40+ 语言高亮，移动端纯等宽文本，无行内结构反馈。 | `MarkdownTextEditor.swift:97` |
| E3 | **编辑/预览硬切换、无联动**。无滚动同步、无"预览点段落→源码跳行"锚点。 | `DocumentView.swift:46` |
| E4 | **大文档解析在 MainActor 同步跑**，10MB 文档卡首帧（snippet 读取反而用了 `Task.detached`，标准不统一）。 | `MarkdownPreviewView.swift:87`、`RecentHistory.swift:185` |

### 2.3 UI 设计专家视角

**亮点（全项目最亮的部分）**
- 设计系统教科书级：`PaperTheme` 单一事实源（`MobileTheme.swift`），动态色 `Color(light:dark:)` 连 Mermaid JS 都同源取色（`:91-128`），改一处全局同步。
- 美学有记忆点：确定性宣纸噪点（seed=42）、朱砂印章、玻璃胶囊受光、TimelineView 流光。
- 性能意识：易变状态隔离成独立 struct（`DocActionBar`/`ChatInputBar`/`ActionButtons`），避免父视图重算。

**关键问题**

| 级别 | 问题 | 证据 |
|---|---|---|
| U1 | **不跟随系统 Dynamic Type**。41 处固定字号 + 自带字号档位，无任何 `dynamicTypeSize`。放大字体用户碰壁，可访问性硬缺口。 | `grep dynamicTypeSize` 全空 |
| U2 | **部分触控目标偏小**（34×34、32×32），低于 44pt 建议。 | `HeroOverlays.swift:63,86,139` |
| U3 | **TimelineView 0.05s 常驻流光**，选中态持续耗电。 | `RootView.swift:195` |
| U4 | **inkSecondary 对比度偏紧**，caption 级小字边缘；AIHero 自定义 overlay 非 sheet，键盘避让需手工保证。 | `MobileTheme.swift:20` |

### 2.4 Agent 设计专家视角

**亮点**
- `MobileAgentContext` 是桌面协议在移动端的正确适配：复用共享 PatchEngine、写目标强校验防路径逃逸（连 `../` 和绝对路径都挡）、shell 空实现优雅降级、`insert_at_cursor` 降级为追加（`MobileAgentContext.swift:79-85`）。
- API Key 进 Keychain + 旧明文迁移（`MobileAISettings.swift:20,50-54`），隐私处理干净。

**关键问题**

| 级别 | 问题 | 证据 |
|---|---|---|
| A1 | **"整篇文档塞进 prompt"是上下文炸弹**。"AI 优化全文"把整个源文（可达 10MB）内联进单条 user 消息，对话历史截断截不掉当前消息，大文档直接撑爆 token / 300s 超时。 | `MarkdownPreviewView.swift:46-69` |
| A2 | **技能是纯 prompt、无工具收窄**。开"Code Review"技能时 agent 仍握有全部写工具。 | `MobileSkills.swift` |
| A3 | agent `openFile` 无确认（同 P4）。 | `MobileAgentContext.swift:124-127` |
| A4 | 300s 超时对移动端偏长，弱网下体验像"卡死"。 | `MobileAISettings.swift:77` |

---

## 三、macOS 客户端评测

### 3.1 产品专家视角

**亮点**
- 完整桌面产品面：文件树、标签页、待办（扫 checkbox）、日历（EventKit）、演讲模式、模板、插件（SKILL.md）、在线分享（NWListener）、Gist、Claude 文件监听。
- 会话恢复可靠：security-scoped bookmark（非裸路径）+ 退出同步落盘 + 恢复时逐 tab 验证文件存在（`SessionStore.swift:10`、`MEditorApp.swift:43`、`AppState+Session.swift:32-33`）。

**关键问题**

| 级别 | 问题 | 证据 |
|---|---|---|
| P1 | **范围失控信号**：一个 Markdown 编辑器里住了六个 App（文档/待办/日历/AI/设置/QuickOpen），设置 30+ 配置项。每个功能都浅，稀释"纸墨从容书写"的定位。产品层最重要的取舍问题。 | `AppSettings.swift:18-47` |
| P2 | **会话恢复不保存光标/滚动位置**。数据在（`cursorLine/cursorColumn`）但没存，重开找不到上次停在哪。 | `AppState+Session.swift:25-71`、`AppState.swift:85-86` |
| P3 | **Stale bookmark 检测了但没用**。`resolveBookmark` 返回 `isStale`，恢复流程未重建，文件移动后会话静默失效。 | `SessionStore.swift:101-113` |
| P4 | **iCloud 场景无 `NSFileCoordinator`/`NSFilePresenter`**，冲突版本没人管，有数据风险（iOS 端反而有协调写）。 | `FileWatcherService` 全代码无协调 |
| P5 | **Agent 会话无整体回滚**。`run_command`/`write_file` 副作用立即生效且不可逆。 | 见 A3 |

### 3.2 编辑器设计专家视角

**亮点（技术含量最高的区域）**
- 原生 NSTextView + 原生 undo，AI 插入/替换走完整变更链进入 undo 栈（`NativeEditorView.swift:68,190-223`）——比 iOS 强。
- 性能工程可教：非连续布局（`:94`）、可见范围高亮 + 2000 字符缓冲（`EditorHighlightScheduler.swift:109-112`）、O(log n) 行偏移二分（`:50-59`）、向量化行构建（`:31-39`）、打字 0.3s / 滚动 0.12s 双防抖、按文件大小自适应预览防抖（`EditorCoordinator.swift:232-240`）。
- 双向滚动同步是真双向：两对 suppress 标志断 echo 环 + `isProgrammaticScroll` 双保险（`ScrollSyncState.swift:9-31`）。
- 图片拖拽会把路径百分号编码 + 剔除 `[`/`]`（`EditorCoordinator.swift:213-224`）。

**关键问题**

| 级别 | 问题 | 证据 |
|---|---|---|
| E1 | **150KB 高亮硬阈值一刀切**。超过即完全跳过高亮，即使代码已有"只高亮可见范围 + 缓冲"能力。应拆分"可见范围高亮"与"全文扫描"门控。 | `NativeEditorView.swift:16`、`EditorHighlightScheduler.swift:87-89` |
| E2 | **diff 接受的写回破坏 undo 语义**。`tab.content = merged` 全文替换绕过 `shouldChangeText`，undo 栈留下"全文清空→恢复"怪异条目，而非"选区替换"。**与 iOS E1 是同一病两面。** | `InlineEditBar.swift:283-287`、`NativeEditorView.swift:167-176` |
| E3 | **`ParagraphDiffer` LCS 是 O(n²) 无门控**。5000 段落 = 25M 次循环，diff review 主线程同步跑。无 Hirschberg 优化。 | `ParagraphDiffer.swift:39-65` |
| E4 | **预览选区映射对重复文本有歧义**。归一化纯文本 literal 匹配，无"候选位置确认"。 | `SourceTextMapper.swift:89` |
| E5 | **流式阶段只显示最后 6000 字符**。5 万字文档判断不了前部改动，可换 `DiffWebView` 渲染路径。 | `DiffReviewOverlay.swift:342-346` |

### 3.3 UI 设计专家视角

**亮点**
- 编辑器字体决策是内行：正文用系统比例字体而非等宽（正确支持 CJK 字形宽度），代码区才切等宽（`NativeEditorView.swift:76`）。
- 欢迎页有产品人格（像素风品牌卡 + 字符闪烁）；空编辑器是 `DotGridBackground`。
- 有设计 token（`DS.Motion`）和主题系统（`PreviewTheme` 联动编辑器/预览）。

**关键问题**

| 级别 | 问题 | 证据 |
|---|---|---|
| U1 | **颜色叙事碎片化**。一条 `InlineEditBar` 里三个强调色来源（`Color.appAccent` / `AIBrand.blue` / `Color.primary.opacity`），编辑器头部用 `theme.craftPrimary`。对比 iOS 全 App 只有一个 `PaperTheme.accent`。 | `InlineEditBar.swift:134,175`、`EditorView.swift:100` |
| U2 | **动效未完全收敛**。有 `DS.Motion` 但散落 `.easeInOut`、`.spring` 字面量；iOS 的三级 spring 收敛做完了，桌面端做了一半。 | `EditorView.swift:56`、`InlineEditBar.swift:88` |
| U3 | **状态栏信息密度偏高**（光标/统计/大小/类型/修改/已保存/分享七项）。 | `StatusBar.swift:14-97` |

### 3.4 Agent 设计专家视角

**亮点（行业级）**
- **`CommandSandbox` 静态命令风险分析是教科书**：blocked/warn/safe 三级（`CommandSandbox.swift:93-150`）、`.commandToken` 匹配避免 `npm run sync` 误杀 `nc`（`:174-197`）、warn 每次确认、safe 按 `command+cwd` 去重（`:240-245`）、cwd 穿越检测（`:206-229`）、skill 白名单（`RunCommandTool.swift:99-104`）、30s 超时 + 16KB 截断——六层纵深。
- 写入包含校验 `validateWriteTarget`（`AgentContext.swift:83-91`）在全部写工具上强制。
- `PatchEngine` 三级降级匹配 + 失败时 `nearbyContext` 回传最近行自纠错（`AgentPatchEngine.swift:12-65,70-88`）。
- At-Mention 有边界设计：UTF-8 fuzzyScore、去重、上限 8 token、单文件 32KB 截断。

**关键问题**

| 级别 | 问题 | 证据 |
|---|---|---|
| A1 | **无 prompt 注入防御，最该补的安全债**。@mention 文件内容原样进 system prompt（代码块包裹但零 sanitization）；用户自定义 prompt 以"务必遵守"最高优先级追加在末尾。引用了含 "Ignore previous instructions" 的文件就直接进上下文。 | `AtMentionContextBuilder.swift:97-103`、`AIChatCoordinator.swift:214-217` |
| A2 | **API Key 明文存 UserDefaults**。注释解释理由（Keychain ACL 绑定 code signature），属明知取舍，但同用户下可读 UserDefaults 的进程都能拿到。签名稳定后应换回 Keychain 或加密。 | `AIService.swift:160-181` |
| A3 | **Agent 写操作无事务回滚**（同 P5）。无会话级快照，diff review 拦不住工作区文件被改/被建。 | — |
| A4 | **login shell 环境注入面**。`-l -i` 执行 + 用户完整 shell 环境注入 `claude` 子进程，rc 文件 PATH 会生效，纵深最后一层依赖用户 shell 干净。 | `RunCommandTool.swift:186-197`、`AIService.swift:336-352` |
| A5 | **上下文炸弹在两条路径复发**。`InlineEditBar` 内联 `Full document: 全文` 无大小门控（`InlineEditBar.swift:198,248-249`）；`read_document` 对激活 tab 走 `tab.content` 全文返回、**绕过磁盘路径的 64KB 截断**（`DocumentTools.swift:34`）。聊天面板本身干净：仅首轮注入、8000 字符封顶（`AIChatCoordinator.swift:202-204`）。 | `InlineEditBar.swift:198,248-249`、`DocumentTools.swift:34` |

---

## 四、跨端结构性对照

| 维度 | macOS | iOS |
|---|---|---|
| 文件系统 | 完整文件树 + 标签 + 会话恢复 | **只有最近列表，无目录浏览** |
| 编辑器 | NSTextView + 语法高亮 + 原生 undo | UITextView 纯文本、无高亮 |
| AI 写回 | diff review + 内联编辑（强） | 插入/替换按钮（弱） |
| Agent 安全 | CommandSandbox 六层纵深 | 无 shell，写路径有包含校验 |
| undo × AI 写回 | **产生坏 undo** | **清掉用户 undo** |
| 上下文管理 | **内联编辑 / read_document tab 路径全文无门控**（聊天面板 8K 封顶，干净） | **优化全文路径全文内联** |
| 设计系统 | 色板碎片化、动效半收敛 | 单色板、全收敛 |

**方向性结论**：桌面端该向移动端学设计系统收敛；移动端该向桌面端学文件浏览和 Agent 安全边界。而"AI 写回 vs undo 栈"与"大文档全文内联进 prompt"两个跨端共性问题，值得单独设计一个统一方案一次性解决，而不是各端修各端的。

---

## 五、Top 行动项汇总

### iOS 端（按投入产出排序）

| # | 事项 | 视角 | 成本 |
|---|---|---|---|
| 1 | iOS 加目录浏览（工作区树，哪怕只到二级） | 产品 | 中 |
| 2 | 修 E1 撤销栈：AI 写入后 shake-to-undo 失效 | 编辑器 | 低 |
| 3 | 大文档不再全文内联进 prompt（A1） | Agent | 低 |
| 4 | 补 Dynamic Type 支持（U1） | UI/可访问性 | 低-中 |
| 5 | agent openFile 加确认（P4/A3） | 产品+Agent | 低 |
| 6 | 顺手：`importableTypes` 三处重复定义抽到一处 | 架构 | 极低 |

### macOS 端

| # | 事项 | 视角 | 成本 |
|---|---|---|---|
| 1 | 补 prompt 注入防御：@mention sanitize + 用户自定义 prompt 风险词筛查（A1） | Agent/安全 | 低 |
| 2 | 修 E2 undo 语义：diff 接受改走 `shouldChangeText` 路径 | 编辑器 | 低 |
| 3 | 会话保存光标/滚动位置 + stale bookmark 重建（P2/P3） | 产品 | 低 |
| 4 | 修 E1 高亮阈值：可见范围高亮不受 150KB 门控 | 编辑器 | 低 |
| 5 | 大文档不再全文内联进 prompt（A5）——与 iOS 同修 | Agent | 低 |

**P1（macOS 功能取舍）和 A2（API Key 存储）是决策题**，其余都是低成本真实缺陷。

---

## 附：语音输入（iOS）决策备忘

2026-08 评审期间对 iOS 端"语音转文字改文档"的结论：

- **纯"语音转文字"不值得做**：iOS 键盘自带听写，用户不用装就有，做出来是"多余的麦克风按钮"。
- **"语音转 Markdown"（口语指令 → 结构 + 可选 AI 整理）**：便宜（SFSpeechRecognizer 一个服务文件 + 复用 `Coordinator` 的 `LineRule`，约 1-2 天 v1），但只是加分项，不是杀手锏。
- **不建议现在做**：它解决"懒得打字"的舒适度，不解决"写好内容"的问题；手机端真正的杠杆是已有的 AI 编辑链路。哪天要版本噱头或路上口述场景被勾住再做不迟。
- 前置条件（若做）：`NSSpeechRecognitionUsageDescription` + `NSMicrophoneUsageDescription` 两条权限；on-device 识别（`supportsOnDeviceRecognition` 运行时可查）。

---

## 六、方向展望（2026-08-08 产品讨论）

> 核心判断：MEditor 的差异化不是「Markdown 编辑器 + AI 聊天」，而是**「有审美的、能真正动手改稿的 AI 写作搭档」**。顺着这个定位，最值钱的方向不是加功能，而是把 AI 从"生成文字"推进到"可信任地落稿"。竞争产品（Obsidian 插件、Notion AI）几乎全停在"给你一段文本你自己粘"，没人解决"AI 改动如何安全落地"——这是能建护城河、且代码里已有骨架（diff review）的地方。

### 值得做的方向（按优先级）

**方向一：AI 编辑的信任闭环 —— 最该做，也最难被抄**
现 diff review 是"骨架没成闭环"。缺的三件事：
- undo 语义正确（对应上文 E2，AI 写回产生坏 undo）
- **改动历史回放**：「这周 AI 改过什么、每处改动前长什么样、一键回滚到 N 步前」——当前完全空白
- 手动改动与 AI 改动分层管理

做完这个，AI 从"会说话的助手"变成"可复盘可追责的编辑"。这是把 `CommandSandbox` 六层安全那个工程水准复制到文档落稿层面——已在安全上证明过深度，值得同力度投入。

**方向二：从「编辑文件」到「完成一篇文章」—— 写作流程闭环**
现在只解决"编辑"这一环。缺写作者真正的工作流：想法捕获 → 大纲 → 长文分节写作 → 终稿打磨 → 发布（Gist/share 已有）。
- 具体落点：**写作目标**（字数/章节/语气）、**AI 按大纲分节续写**（替代整篇塞进 prompt）、**批注/审阅模式**
- 「纸墨」审美本是长文写作主场，但产品没有"写作计划/进度"这个概念——这是纸墨定位与实际功能之间的裂缝

**方向三：移动端改定位 —— 做「捕获 + 审阅」，别做「编辑器」**
定位修正，比加功能重要。手机上无法舒适写长文，iOS 端追平桌面端是死路。该做：
- 随手捕获（速记、摘录、语音草稿）
- 通勤审阅（读、批注、改错字——手机的天然场景）
- AI 摘要 / 划重点

移动端从"薄壳移植"变成"写作流程的另一端"，与方向二互为表里。

**方向四：Agent 纵深 —— SKILL.md 是种子，值得长成生态**
现状技能只做 prompt 注入、没绑工具、没做工具收窄（上文 A2）。值得做的是把常用写作任务（周报、PRD、会议纪要、润色）做成**可组合、带工具边界**的技能，让用户能自己写。把"内置 AI"变成"用户可扩展的 AI 工作台"，复利极高。

### 不建议的方向

- **不要继续在 App 内堆功能**——待办、日历已摊薄「从容书写」定位（上文 P1），继续加会加重
- **不做语音转写**（已评估，见附录）
- **不做多人协作 / 模板市场**——"做大"的方向，现在做是撒胡椒面，核心闭环稳了再说

> 一句话：**信任闭环（方向一）是护城河，写作流程（方向二）是身份，移动端定位（方向三）是纠偏，技能生态（方向四）是复利。** 前两个应立即排进迭代。

---

## 七、代码质量专项评审（2026-08-08，专家面）

> 范围：agent 层全部核心文件（AgentRunner / AgentContext / AgentFileRepository / AgentPatchEngine / 两个 Backend / 四个工具域 / AIChatCoordinator / AIConversationStore）+ 45 个测试文件清单。**本专项只评估代码质量，不改任何代码。**

### 7.1 整体代码质量 —— A-

突出的是三种纪律，不是单块代码：

1. **并发正确性**：SSE chunk 回流用 `DispatchQueue.main.async` 而非 `Task { @MainActor }`，注释明确解释原因——main queue 严格 FIFO 保证 chunk 顺序，Task 调度顺序不保证（`AgentRunner.swift:190-208`）。超时用 task group 双任务赛跑 + `cancelAll`，且说明了为何 onComplete 不在超时分支调用（`AgentRunner.swift:124-149`）。
2. **continuation 泄漏防护**：命令确认框用 `withCheckedContinuation` 挂起，最怕超时期间弹出导致 continuation 永不恢复。三重保险：`PendingCommand.answered` 幂等守卫（`AIConversationStore.swift:19-20`）、Runner 超时主动 reject（`AgentRunner.swift:144`）、正常结束兜底 reject（`:327`）。
3. **工具结果配对完整性**：中断时 `reconcileToolResults` 为未应答的 tool_call 补合成 error result，保证历史配对严格，否则下轮 API 400（`AgentRunner.swift:387-405`）。
4. **测试文化行业级**：45 个测试文件中 agent 层独占 10 个（`AgentRunnerMultiTurnTests`、`AgentSSEStabilityTests`、`AgentTruncationStabilityTests`、`AgentWriteConfinementTests`、`CommandSandboxTests`、`IntentClassifierTests` 等），配专门 `Mocks/`。**agent 层是全书测试覆盖率最高的区域。**
5. **协议分解干净**：`AgentContextProtocol = DocumentContext & WorkspaceContext & ShellContext`（`AgentContextProtocol.swift:71`），窄接口带 mock 默认实现；`AgentBackend` 协议 + Factory 让新增后端零改动 Runner（`AgentBackend.swift:111-126`）。

一般性弱点（agent 层无关，全局债）：

| 问题 | 证据 |
|---|---|
| AppState 星型耦合（10 Manager + 14 回调） | `AppState.swift` |
| `AgentRunner` 手工转发 `state` 属性略冗余，可直接暴露 `state` | `AgentRunner.swift:20-39` |
| 超时赛跑模式在两处重复（Runner / RunCommandTool），可抽公共工具 | `AgentRunner.swift:125`、`RunCommandTool.swift:146` |
| `runner.cancel()` 直接调用时无命令确认兜底（仅超时路径和 `AIConversation.cancelStreaming` 有），直接调用方会挂住 | `AgentRunner.swift:153-163` |

### 7.2 核心 Agent 层质量 —— A-

**行业级的强项（全书最值钱的部分）**

1. **CommandSandbox + RunCommandTool 六层纵深**（`CommandSandbox.swift`）——blocked/warn/safe 分级、`.commandToken` 防误杀、cwd 穿越检测、per-key 审批缓存。
2. **写入围栏**：`validateWriteTarget` 强制在全部写路径（createFile/writeFile/createDirectory/patchFile，`AgentContext.swift:83-106`），配 `AgentWriteConfinementTests.swift`；无工作区时回退"仅允许已打开 tab"，是安全默认。
3. **截断体系系统化**：read 64KB 截断、full read 5MB 上限、搜索 100 条上限；会话滑动窗口裁剪 agentHistory 时**显式保证不切断 tool_call / tool_result 配对**（`AIConversationStore.swift:185-189`）。
4. **PatchEngine 三级降级 + nearbyContext 自纠错**（`AgentPatchEngine.swift:70-88`）。
5. **ClaudeCLIBackend IntentScorer**——关键词权重 + 负向词 + 阈值 + mixed 保守默认，收窄工具集方向聪明。

**真缺陷（按严重度排序）**

| # | 级别 | 缺陷 | 证据 |
|---|---|---|---|
| 1 | 安全债 | **system prompt 主动要求服从 + @mention 内容零净化**。`AIChatCoordinator.swift:178` 写明 "NEVER refuse a file operation request"，而 @mention 文件内容原样进 system prompt——含恶意指令的文件可诱导覆盖工作区内任何文件。写入围栏只挡工作区外。**是当前层最该补的洞。** | `AIChatCoordinator.swift:178`、`AtMentionContextBuilder.swift:97-103` |
| 2 | 正确性 | **`read_document` 对激活 tab 绕过 64KB 截断**。磁盘路径 `readFile` 截断 64KB（`AgentFileRepository.swift:73`），但 `read_document` 不传 filename 走 `tab.content` 全文返回（`DocumentTools.swift:34`），10MB 文档一次读穿。 | `DocumentTools.swift:34` |
| 3 | 行为 bug | **safe 命令审批缓存是 per-run 而非 per-session**。`_approvedCommandKeys` 存于 AgentContext 实例（`AgentContext.swift:147`），但 macOS 每轮消息都 `AgentContext.make()` 新建（`AIChatCoordinator.swift:27`）——同一 safe 命令每个对话轮次重新弹框，与 `RunCommandTool.swift:24` 注释"本次 agent session 内不再弹框"不符。iOS 端 context 建于 init、活整个会话，缓存真有效（`ChatModel.swift:50`）。两端行为不一致。 | `AgentContext.swift:147`、`AIChatCoordinator.swift:27` |
| 4 | 健壮性 | 多步写操作无原子回滚（同 3.4 A3），`write_file`/`create_file` 对工作区其它文件的副作用不可逆。 | — |

### 7.3 对前文的修正

- **A5（上文 3.4）**：聊天面板**有**门控——`systemContext` 仅首轮注入、8000 字符封顶（`AIChatCoordinator.swift:202-204`），不是"聊天/内联路径全文内联"。真正的全文炸弹只有两条：`InlineEditBar` 的 `Full document:`（`InlineEditBar.swift:198,248-249`）与 `read_document` 的 tab 全文返回（`DocumentTools.swift:34`）。
- 跨端对照表"上下文管理"一行已按此收窄。

**专项结论**：这层代码是"敢把 Agent 交给用户的工程"——安全架构、截断体系、并发正确性是教科书级。短板不在工程而在**系统提示的信任边界**（7.2 #1）：防住了命令注入，却没防住提示注入，而后者是打开整个安全层的钥匙。

---

## 八、上下文成本审计（2026-08-08，真实付费触发）

> 触发场景：当天用 AI 修改两个文档，费用约 ¥3。经查证，agent 层的上下文管理存在真实成本缺陷，每条都对应具体代码路径。**本审计只改文档，不改代码。**

### 8.1 核心机制：全文读取结果变成"永久年金"

`read_document` 对打开文档走 `tab.content` **全文返回、无任何门控**（`DocumentTools.swift:34`）；读入的全文作为 tool result 存进 `agentHistory`（`AIChatCoordinator.swift:148-150`），**此后每一轮对话都把这段全文结果整段重新发给模型**——一次全文读取不是付一次钱，而是付一辈子钱。

典型"改文档"流程（假设单篇 6 万字符 ≈ 1.5 万 token）：
1. `read_document` 全文 → 进历史
2. `patch_document` 小改 → 小结果
3. **再 `read_document` 验证**（LLM 几乎必做）→ 又 1.5 万 token，且历史已累积
4. 每轮全量重发累积历史，第 5 轮时历史 ≈ 4-5 万 token

改两篇、每篇 6-10 轮，估算 **80-150 万输入 token**，与 ¥3 量级吻合。

### 8.2 放大因素（按影响排序）

| # | 因素 | 证据 | 影响 |
|---|---|---|---|
| 1 | `read_document` 全文无门控 + **无"读取行区间"工具**，修改后只能全文重读 | `DocumentTools.swift:34` | 最大头 |
| 2 | **内联编辑路径 `Full document:` 无截断**——编辑器内 AI 优化每次动作整篇进 prompt | `InlineEditBar.swift:198,248-249` | 大 |
| 3 | **token 估算对中文严重低估**：`estimatedTokenCount = 字符数/4`（`AIConversationStore.swift:144-148`）。中文约 1-1.5 字符/token，非 4——滑动窗口截断（102K 触发）对中文会话几乎永不准时，历史一路涨到 API 拒收。**中文优先应用的量级级 bug。** | `AIConversationStore.swift:144-153` | 大 |
| 4 | **无 prompt caching**：Anthropic 协议未发 `cache_control`（`RestAgentBackend.swift:311-340`），同一段历史每轮全价重付；DeepSeek 则自动缓存（有省但不可控） | `RestAgentBackend.swift:311-340` | 中-大 |
| 5 | `write_document` 整篇替换：输出整篇、`max_tokens: 8096` 封顶，大文档分多轮重写 | `RestAgentBackend.swift:331` | 中 |

### 8.3 不改代码立即可做

1. 改文档前先让 agent `search_document` 定位，确认位置再小片段 `patch_document`，不开篇全文读取。
2. 明确指示"不要全文重读，用 search 验证"。
3. 避免 `write_document` 整篇重写，永远 patch 小改。

### 8.4 若要改代码（按性价比排序）

1. **prompt caching**：Anthropic 协议在 system + 每轮 tool 结果前插 `cache_control`，重发历史成本降 ~90%，改动最小、收益最大。
2. **修 token 估算**：CJK 按 ~1.5 字符/token（或分语言系数），让截断阀准时触发。
3. **加 `read_document` range 参数**（读 30-80 行区间），从根上消灭全文重读。
4. **InlineEditBar 全文对齐聊天面板 8K 截断**（`AIChatCoordinator.swift:202-204` 已有参照）。

---

## 九、窗口 chrome 专项：红绿灯 / 侧边栏 / tab 条（2026-08-08）

> 触发场景：桌面端侧边栏 + 红绿灯 + tab 区域反复出现两种病——① 红绿灯背后小区域背景色对不上（"色差补丁"）；② 磨砂横条全宽遮住文件 tab。追到 commit 历史，根因是 `2f0766c` 移除 NSToolbar 的决定。**本专项只评不改。**

### 9.1 现状：自制窗口 chrome（与 AppKit 打架）

`WindowConfigurator.swift` 是一套完整手工手术，共四刀：

```swift
w.toolbar = nil                          // ① 干掉 toolbar
constrainTitlebarToLights(w)             // ② 把 titlebar 容器压到 92px
makeTitlebarBackgroundTransparent(w)     // ③ 按类名隐藏 NSTitlebarBackgroundView
repositionTrafficLights(w)               // ④ 硬编码坐标手工挪红绿灯
```

配套：tab 条 `.background(.bar)` 顶到窗口最顶（`AppShell.swift:316`）、侧边栏卡片 `ignoresSafeArea(.top)` 伸手进标题栏（`:107`）、红绿灯落卡片内靠 `padding(.top, 40)`（`:59`）。

**两种病是同一件事的两面**：内容占领了标题栏区域，但系统标题栏背景层（`NSTitlebarBackgroundView`）还在底下作祟。压到 92px → 露出色差补丁；不压 → 横条遮 tab。在 92px 与全宽之间左右横跳，本质是给一个不该碰的系统层打补丁。`repositionTrafficLights` 里硬编码的 `topGap=15/leftPad=16/spacing=20`（`WindowConfigurator.swift:121-124`）是 Apple 标准按钮度量，每次 macOS 升级都要重对。

### 9.2 溯源：commit `2f0766c` 的记录不成立

记录原文（2026-06-13「ui: remove NSToolbar entirely」）：

> Root cause of visible top bar: NSToolbar renders its own visual material even with titlebarAppearsTransparent. Solution: remove it.

**观察对、结论错，四条理由：**

1. **"toolbar 会画材质"不是 bug，是定义。** 统一工具栏的磨砂材质就是 macOS 原生外观，Finder/Notes/Safari 全有。把标准 chrome 当缺陷清除 = 误诊。
2. **时间线证明弃疗了已修好的标准方案。** 更早的 `65db3c4` 已修好 overlap（移除 `ignoresSafeArea(.top)`、toolbar 收回 `.unifiedCompact`），那一刻起就是标准 Finder 布局：toolbar 带在上、tab 条在下互不遮挡。之后 `2f0766c` 仍删 toolbar——拿已解决的旧痛当理由。
3. **反讽：删掉 toolbar 后横条照样在，只是更难藏。** 留着 `fullSizeContentView`，无 toolbar 时 `NSTitlebarBackgroundView` 仍画磨砂横条。有 toolbar 时这条是"合法的 toolbar"，系统负责；删掉后变成"非法的标题栏背景"，必须用私有手术去藏。**逃掉的横条变成了更难藏的横条。**
4. **后果是连续四连补丁：** `a73a160`（白底圆角漏出）→ `582e74d`（macOS 26 红绿灯丢失）→ `75bab29`（横条遮 tab，压 92px）→ `cd64e4f`（92px 色差补丁）。每一条都是给移除决定的善后，根上色差至今未解。

### 9.3 Apple 的优雅方案（两条路线，都是系统支持）

**路线 A —— unified toolbar（省事、macOS 26+ 稳）**
- 保留已有底座：`titleVisibility = .hidden`、`titlebarAppearsTransparent = true`、`fullSizeContentView`、`.windowStyle(.hiddenTitleBar)`（`MEditorApp.swift:19-22,51`）。
- 删 `w.toolbar = nil` 及 `constrainTitlebarToLights` / `makeTitlebarBackgroundTransparent` / `repositionTrafficLights` 四刀。红绿灯由系统摆进 toolbar 磨砂带左端，垂直居中。
- ContentView 加 `.toolbar { }`，把散落的 ChromeButton（新建/AI 优化/预览切换/分享）收敛为真实工具栏项——磨砂带不再"空横条遮 tab"。
- tab 条移出标题栏区：删 `AppShell.swift:316` 的 `ignoresSafeAreaEdges: .top`，加 toolbar 后窗口服务自动把内容排在磨砂带下方。"横条遮 tab"在结构上消失。

**路线 B —— Bear 式沉浸（红绿灯落在纸色卡片上，贴合纸墨品牌）**
- 保持无 toolbar，但改走"内容盖住标题栏"：卡片材质一路铺到窗口最顶、完全盖住系统标题栏区域，只留系统红绿灯落在自己材质上。
- 删 `makeTitlebarBackgroundTransparent` 的按类名隐藏，改用受支持的方式让标题栏真正透明；删 `repositionTrafficLights`（系统默认位置，不手工挪）。
- 现状只差"卡片顶上那 6pt 缝隙把系统背景漏出来"（`AppShell.swift:102`）——补上即闭环。

### 9.4 关键铁律

**红绿灯永远坐在标题栏这个半透明模糊区里，任何不透明颜色放它后面都会露出一道缝。** 所有贴着红绿灯/标题栏的层必须是 vibrancy 材质（`.sidebar` / `.bar` / `SidebarVibrancyView`），不是纯色——Apple 带颜色侧边栏（Mail/Finder）全是材质而非纯色，正是为此。

**结论**：`2f0766c` 的判断站不住。二选一：要省事走路线 A（回 toolbar），要沉浸走路线 B（Bear 式材质盖顶）。现在这条路（压容器 + 藏视图 + 挪按钮）不是系统支持的路线，每次 macOS 升级都塌。

---

## 十、窗口 chrome 迁移方案（路线 A，2026-08-08 待执行）

> **决策**：走路线 A——unified toolbar，红绿灯交给系统摆（用户拍板"苹果的都用了"）。本方案只写不改，明天按此执行。
> 前提：share/export 已在 DocumentActionBar、文件操作在 SidebarBottomBar、编辑/预览切换只在 QuickOpen——**按钮早就不在顶部条里了，所以这次几乎不用搬迁任何按钮**，只需"删手术 + 加真 toolbar + 把 tab 条降下来"。改动小、风险低。

### 1. `WindowConfigurator.swift` —— 删手术（核心）

- 删 `w.toolbar = nil`（`configure` 内，约 :64）
- 删三个手术函数：`constrainTitlebarToLights` / `makeTitlebarBackgroundTransparent` / `repositionTrafficLights`
- 删 `reapply()` + `didResize/didBecomeKey/didResignKey` 通知观察（:38-55，只重放手术）
- **保留**：`titleVisibility = .hidden`、`titlebarAppearsTransparent = true`、`fullSizeContentView`、`installDoubleClickZoom`
- 文件缩到 ~40 行，不再碰任何私有视图类 → macOS 26+ 无按钮丢失风险

### 2. 加真 toolbar —— `ContentView.swift` 根部加 `.toolbar { }`（:23 `.background(WindowConfigurator())` 旁）

```swift
.toolbar {
    ToolbarItemGroup {
        Button(L("menu.newFile")) { state.showingTemplatePicker = true }   // 新建
        Button(sidebar 切换) { workspaceUI.toggleSidebar() }
        Button(编辑器切换) { workspaceUI.toggleEditor() }
        Button(预览切换)  { workspaceUI.togglePreview() }
    }
}
```

- 红绿灯自动进 toolbar 磨砂带左端，系统摆位
- 编辑/预览切换从"只在 QuickOpen"升级为一级入口（顺带补功能）
- share/export/theme **不动**（已是 DocumentActionBar 上下文按钮）
- 专注模式可选 `.toolbar(removing: .automatic)` 隐藏 toolbar，沉浸更好

### 3. `AppShell.swift` —— tab 条降级为普通内容行

- `TopToolbar`：删 `.background(.bar, ignoresSafeAreaEdges: .top)`（:316），换普通背景——系统 toolbar 成为唯一顶部磨砂带，否则双条
- 删侧边栏隐藏时的 `Color.clear.frame(width: 84)` 预留 + 那个 ChromeButton（:297-309）——sidebar 切换已进 toolbar，tabs 从内容左缘起
- 专注模式顶部 `Color.clear.frame(height: 38)`（:127）改为自适应安全区

### 4. `AppShell.swift` —— 侧边栏卡片定位（推荐 Finder/Notes 几何）

- 删 `.padding(.top, 40)`（:59，红绿灯落卡片内的补偿）和 `.ignoresSafeArea(.container, edges: .top)`（:107）
- 卡片从安全区顶开始（toolbar 带下方），红绿灯浮在 toolbar 带上，零布局换算
- （备选 Bear 式：保留 `ignoresSafeArea(.top)` 让卡片延伸进 toolbar 带、红绿灯落纸色卡片——但 toolbar 项会叠卡片上。走推荐项。）

### 5. `MEditorApp.swift` —— 无需改动

`.windowStyle(.hiddenTitleBar)`（:51）+ 透明标题栏 + `fullSizeContentView` 已是 unified toolbar 正确底座。

### 验证

1. 编译通过
2. 运行检查：红绿灯在左上角 toolbar 带上、三键齐全垂直居中（macOS 14/15/26 各看一眼）；背后无任何色差补丁；tab 条在 toolbar 下方无遮挡；拖窗口/双击缩放可用；sidebar、编辑/预览切换从 toolbar 可用；侧边栏隐藏时 tab 条从内容左缘起；专注模式沉浸正常
3. 回归：打开文件、切 tab、分享/导出不受影响

### 备注

- 重心是"删掉自作主张的部分"而非"加新功能"——四刀全删
- 若担心 `.hiddenTitleBar` + toolbar 在个别版本表现，先最小 toolbar（仅 1 个 Item）跑通再补按钮

---

*本文档由代码评审会话自动整理生成，证据均来自源码阅读，未运行测试验证。*
