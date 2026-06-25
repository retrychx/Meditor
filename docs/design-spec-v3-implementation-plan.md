# MEditor UI v3 Implementation Plan

基于 [design-spec-v3.md](design-spec-v3.md) 的前端落地清单。

目标不是记录所有想法，而是给实现提供明确的阶段、模块、依赖关系和验收标准。

---

## 1. 实施原则

- 先搭骨架，再修皮肤
- 先统一状态模型，再做组件细节
- 先做键盘和结构，再做动效
- 每个阶段都必须可运行、可验证、可回退

---

## 2. 里程碑

### Milestone 1: App Shell

目标：

- 建立三栏布局
- 建立顶部工具区
- 建立左侧导航与 Tab 的视觉规范
- 建立设计 token

交付物：

- Layout 容器
- Top Toolbar
- Left Sidebar
- Tab Bar
- Right Panel 容器
- Theme Token 文件

### Milestone 2: Document Workspace

目标：

- 建立中央文档工作区
- 建立文档标题区和内容宽度体系
- 建立块级基础交互状态

交付物：

- Document Header
- Editor Surface
- Block Row 基础容器
- Hover / Selected / Focus 状态

### Milestone 3: Context Panels

目标：

- 建立右侧上下文面板系统
- 明确各面板的切换规则

交付物：

- Panel Router
- Insert Panel
- Style Panel
- Page Info Panel
- Comments Panel
- Share Panel

### Milestone 4: Command System

目标：

- 建立 Slash Command
- 建立 Quick Open
- 建立搜索分层

交付物：

- Slash Menu
- Command Palette
- Sidebar Filter
- In-Document Find
- Global Search Results Panel

### Milestone 5: Polish

目标：

- 收尾动效
- 完成深色模式
- 完成焦点模式
- 完成细节验收

交付物：

- Motion Token
- Focus Mode
- Empty / Loading / Error 状态
- Dark Mode 调优

---

## 3. 模块拆分

### 3.1 Design Tokens

需要落地：

- 颜色 token
- 间距 token
- 圆角 token
- 阴影 token
- 动效 token
- 层级 token

建议输出：

- `tokens/color`
- `tokens/spacing`
- `tokens/radius`
- `tokens/shadow`
- `tokens/motion`
- `tokens/z-index`

验收标准：

- 不允许在业务组件中散落硬编码颜色
- Light / Dark 可通过主题切换覆盖

### 3.2 App Shell

组件：

- `AppLayout`
- `TopToolbar`
- `TabBar`
- `Sidebar`
- `RightPanelHost`
- `ResizableSidebarHandle`

关键状态：

- `sidebarCollapsed`
- `sidebarWidth`
- `activeTabId`
- `rightPanelType`
- `rightPanelOpen`
- `focusMode`

验收标准：

- 左侧栏可收起和拖拽
- 右侧面板开关不会导致主布局跳动
- Tab 切换有稳定的 active 状态

### 3.3 Sidebar

子模块：

- `SpaceSwitcher`
- `SidebarSearchInput`
- `SidebarPrimaryNav`
- `SidebarTree`
- `SidebarFooter`

关键交互：

- 树节点展开收起
- 当前项高亮
- hover 弱操作显现
- 拖拽排序和归档预留

验收标准：

- 树结构可承载多级节点
- 搜索只过滤当前上下文
- 当前文档路径有明确表达

### 3.4 Toolbar

子模块：

- `NavControls`
- `DocumentBreadcrumb`
- `ToolbarActions`

关键动作：

- Toggle Sidebar
- Search
- Share
- Comments
- Layout / Preview Toggle
- More

验收标准：

- 工具区在窄宽度下不会挤爆
- 主要动作可键盘聚焦

### 3.5 Document Workspace

子模块：

- `DocumentHeader`
- `EditorViewport`
- `EditorCanvas`
- `BlockList`
- `BlockRow`
- `BlockHandle`
- `BlockActions`

关键状态：

- `activeBlockId`
- `selectedBlockIds`
- `hoveredBlockId`
- `editorMode`

验收标准：

- 文档宽度在不同窗口尺寸下稳定
- Block hover 不引发错位
- Selected 和 Focus 状态清晰区分

### 3.6 Right Panel System

子模块：

- `RightPanelRail`
- `RightPanelHost`
- `RightPanelHeader`
- `PanelTabs` 或 `PanelSwitcher`
- `InsertPanel`
- `StylePanel`
- `PageInfoPanel`
- `CommentsPanel`
- `SharePanel`
- `SearchResultsPanel`

关键状态：

- `panelType`
- `panelContext`
- `panelPinned`

验收标准：

- 右侧有稳定的细控制条，承载 Insert / Style / Info / Comments / Share / Search / Outline 入口
- 同一时刻只出现一个主面板
- 切换面板不叠多个浮层
- 面板头部固定，内容区滚动

本地 Craft 检查结论：

- Craft 的 macOS 包内存在 `v2BlockDetailsMacSideControls`、`v2BlockDetailsMacSideControlButton`、`v2BlockDetailsMacSideControlsPanelType`、`v2BlockDetailsMacSideControlsPinnedState`
- 右侧交互不是纯顶部工具栏，而是“侧边小控制条 + 可固定上下文面板”
- Insert / Style / Page Info / Share / Comments 应该作为同一套右侧面板系统中的不同 panel，而不是散落成多个独立 popover

### 3.7 Command System

子模块：

- `SlashMenu`
- `CommandPalette`
- `CommandList`
- `CommandInput`
- `SearchResultsList`

关键状态：

- `commandPaletteOpen`
- `slashMenuOpen`
- `query`
- `activeCommandIndex`

验收标准：

- 全流程可键盘完成
- 支持模糊过滤
- 最近项和分组显示正确

---

## 4. 推荐开发顺序

### Phase 1

- 建 token
- 建 `AppLayout`
- 建 `Sidebar`
- 建 `TopToolbar`
- 建 `TabBar`

先不要做：

- 复杂动画
- 真正的数据拖拽
- 右侧业务面板细节

### Phase 2

- 建 `EditorViewport`
- 建 `BlockRow`
- 建 block 的 hover / selected / focus
- 建 `DocumentHeader`

先不要做：

- 多种复杂块类型
- 大量格式化能力

### Phase 3

- 建 `RightPanelHost`
- 先做 `InsertPanel` 和 `StylePanel`
- 再补 `PageInfoPanel`、`CommentsPanel`、`SharePanel`

### Phase 4

- 建 `SlashMenu` 或先落轻量 Slash expansion
- 建 `CommandPalette`
- 建 `In-Document Find`
- 建 `Global Search Results`

### Phase 5

- 建深色模式
- 建焦点模式
- 补空态、加载态、错误态
- 做动效收尾

---

## 5. 工程约束

### 5.1 状态管理

建议拆成三类状态：

- 布局状态
- 编辑器状态
- 命令与面板状态

不要把全部 UI 状态塞进单一 store。

### 5.2 组件边界

要求：

- Shell 组件不直接感知块编辑细节
- Right Panel 不直接管理编辑器内部状态，只消费 context
- Command System 通过统一 action 接口触发，而不是直接操作各处 DOM

### 5.3 样式策略

要求：

- 设计 token 先行
- 组件样式基于 token
- 交互态统一命名

建议状态类命名：

- `is-hovered`
- `is-selected`
- `is-focused`
- `is-active`
- `is-collapsed`

---

## 6. 验收清单

### 6.1 Layout

- 左侧导航宽度可调
- Tab 无底部蓝线
- 顶部工具区稳定
- 右侧面板不抢主内容层级

### 6.2 Editor

- 页面最大宽度合理
- 块 hover 反馈明确
- 选中态和焦点态不混淆
- 多选有清晰操作出口

### 6.3 Commands

- `/` 可以插入内容
- `Cmd/Ctrl + P` 可以打开全局 palette
- `Cmd/Ctrl + K` 保留给 Markdown 链接插入
- 当前文档搜索和全局搜索行为不同
- 所有命令面板支持键盘导航

### 6.4 Visual

- 背景层次明确
- 分割线依赖被降到最低
- Light / Dark 均可用
- 动效短且不扰动

---

## 7. 风险点

### 风险 1: 先做皮肤，后补结构

后果：

- 最终会返工布局和状态模型

### 风险 2: 右侧面板做成一堆独立弹层

后果：

- 信息架构会碎
- 键盘流会断

### 风险 3: Quick Open 和 Search 混成一个功能

后果：

- 用户无法建立稳定心智模型

### 风险 4: 编辑区留白过大

后果：

- 看起来高级，实际编辑效率下降

### 风险 5: Selected / Focus / Hover 状态过于接近

后果：

- 桌面端操作成本上升

---

## 8. 建议的首批任务单

1. 建立主题 token 和基础语义变量
2. 重做主布局容器与三栏结构
3. 重做左侧导航和 Tab 样式
4. 重做顶部工具区
5. 调整文档内容区宽度、字号、间距
6. 建立块级基础容器和 hover / selected / focus 状态
7. 建立右侧面板 host 与 panel routing
8. 接入 Slash Menu 和 Quick Open

---

## 9. 当前落地状态

已完成：

- `WorkspaceUIState` 承接 sidebar/editor/preview/focus/rightPanel 等布局状态
- `AppShell` 承接顶部工具区、左侧栏、编辑区、预览区、右侧 rail、右侧 panel、底部状态栏
- 左侧栏已从系统 `NavigationSplitView` 改为自管 shell 区域，内容上移到 titlebar，给 macOS 交通灯预留 Craft 式侧栏内空间
- 顶部 tab bar 已从内容区上方的系统标题栏下移除，改为贴到自定义顶栏区域
- `RightPanelRail` 建立 Insert / Style / Page Info / Comments / Share / Search / Outline 稳定入口
- `RightPanelHost` 已接入 Insert、Style、Page Info、Share、Search、Markdown Outline 以及 Comments 空态
- `SearchResultsPanel` 已支持文件名/路径匹配、异步正文扫描、结果摘要、按行跳转
- `CommentsPanel` 已支持文档级本地评论、解决状态、删除，不写入源 Markdown 文件
- `QuickOpenSheet` 已从文件打开升级为文件 + actions 的 Command Palette
- `EditorView` 已加入文档标题区
- `NativeEditorView` 已支持光标附近 Slash Menu，并可用上下键、回车、Tab、空格、Esc 完成操作

已验证：

- `swift build` 通过
- `git diff --check` 通过

保留风险：

- 完整块级编辑器尚未落地，当前仍基于 `NSTextView`
- 全局搜索目前是按需异步扫描，尚未做持久化内容索引
- Comments 目前是文档级本地备注，不是 anchored block/thread 评论
