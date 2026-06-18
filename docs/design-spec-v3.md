# MEditor UI Design Spec v3

目标：在保留 `Craft` 的层次感、圆角和呼吸感的同时，引入 `Linear` 的键盘优先和状态克制，但不照搬任何单一产品的外观。

---

## 1. 产品方向

v2 解决的是视觉风格问题，v3 解决的是交互骨架问题。

MEditor 的桌面端应当被定义为：

- 一个以文档和块编辑为核心的工作台，而不是单纯的 Markdown 编辑器
- 一个由左侧导航、中央内容、右侧上下文面板构成的三栏系统
- 一个默认鼠标可用、但对键盘重度优化的编辑环境
- 一个用背景层次和空间节奏建立结构，而不是依赖强边框和装饰线的界面

设计关键词：

- 安静
- 轻层次
- 圆角
- 上下文驱动
- 键盘优先
- 块级编辑

---

## 2. 核心信息架构

### 2.1 主界面结构

桌面主窗口采用以下结构：

1. 左侧导航栏
2. 顶部窗口工具区
3. 中央文档工作区
4. 右侧上下文面板

不是所有区域都永久显示。

默认状态：

- 左侧导航栏显示
- 顶部工具区显示
- 中央文档工作区显示
- 右侧上下文面板按需显示

焦点模式：

- 左侧导航栏可隐藏
- 顶部工具区压缩
- 右侧面板自动收起
- 中央内容区获得最大宽度

### 2.2 左侧导航层级

左侧导航不是单一文件树，而是分层导航：

1. Workspace / Space 切换
2. 顶层入口
3. 文件夹 / 集合 / 最近访问
4. 当前层级下的文档树

顶层入口建议包含：

- All Docs
- Recent
- Favorites
- Shared
- Trash

文档树规则：

- 默认展示当前集合上下文，而不是全量无限树
- 文件夹支持折叠
- 当前文档路径在顶部或标题区展示
- 支持拖拽排序、拖拽归档、拖拽到文件夹

### 2.3 中央内容区层级

中央区域内部再分为：

1. Tab 区
2. 文档标题区
3. 编辑 / 预览主体
4. 底部状态与辅助操作区

### 2.4 右侧面板体系

右侧面板不是一个通用抽屉，而是一组互斥的上下文面板。

建议至少定义：

- Insert Panel
- Style Panel
- Page Info Panel
- Comments Panel
- Share Panel
- Search Results Panel

原则：

- 同一时刻只展开一个主面板
- 面板从右侧固定区域切换，不使用全屏 modal 替代
- 面板宽度固定为主，内容滚动
- 面板属于当前文档上下文，而不是全局浮层

---

## 3. 交互模型

### 3.1 编辑模型

MEditor 应采用块级编辑模型，而不是“整页 textarea + 工具栏”模型。

基础块类型：

- Paragraph
- Heading
- Todo
- Bullet List
- Numbered List
- Quote
- Code Block
- Divider
- Table
- Image
- File Card
- Link Card
- Embedded Object

每个块都有 3 种交互状态：

- Rest
- Hover
- Active / Selected

Hover 时出现轻量控制：

- 拖拽手柄
- 插入入口
- 更多操作

Selected 时出现上下文动作：

- 样式
- 移动
- 转换类型
- 复制链接
- 删除

### 3.2 多选模型

块支持多选，这是桌面端高频能力。

多选后顶部不弹重工具栏，使用轻量上下文条：

- 固定在选择区域附近，或固定在右侧面板顶部
- 提供批量移动、样式、复制、删除、组合等动作

### 3.3 Slash Command

`/` 是一级入口，不是附属功能。

Slash 面板要求：

- 在光标附近出现
- 支持模糊搜索
- 支持键盘上下选择和回车确认
- 分组展示
- 最近使用项前置

一级分组建议：

- Basic
- Media
- Structure
- Data
- Insert
- AI

当前落地策略：

- 第一阶段不重写编辑器为完整 block model
- 先在原生 `NSTextView` 中支持光标附近 Slash Menu
- Slash Menu 支持 `/h1`、`/h2`、`/todo`、`/quote`、`/code`、`/table` 等 Markdown 展开
- Slash Menu 支持上下键、回车、Tab、空格、Esc
- 后续再把 Markdown 文本展开升级为真正的块转换

### 3.4 Quick Open

Quick Open 是全局入口，优先级高于侧边栏搜索。

触发方式：

- `Cmd/Ctrl + P`
- `Cmd/Ctrl + Shift + P` 作为显式 Command Palette 入口

说明：

- MEditor 现有 `Cmd/Ctrl + K` 已用于插入 Markdown 链接，不应被全局命令面板抢占

用途：

- 打开文档
- 打开最近页面
- 搜索块内容
- 跳转命令
- 切换面板

Quick Open 应是全局 Command Palette，而不是只查文件名。

### 3.5 Search

搜索分三层：

1. 侧边栏快速过滤
2. 当前文档内查找
3. 全局搜索

不要混成一个搜索框。

规则：

- 侧边栏搜索只影响当前树
- 文档内查找显示命中高亮和结果计数
- 全局搜索可在右侧 Search Results Panel 中展示结果摘要和路径

---

## 4. 视觉系统

### 4.1 设计原则

- 层次分明：Sidebar < Chrome < Content
- 大圆角：所有交互元素采用统一圆角体系
- 轻边界：尽量不用硬分割线
- 呼吸感：通过 padding 和留白建立秩序
- 动效克制：只在切换、展开、聚焦时提供反馈

### 4.2 色彩系统

#### Light Mode

| Token | 值 | 用途 |
|-------|-----|------|
| `bg-sidebar` | `#F5F5F7` | 左侧导航背景 |
| `bg-chrome` | `#FAFAFA` | 顶部工具区 / Tab 区 |
| `bg-content` | `#FFFFFF` | 内容背景 |
| `bg-panel` | `#FBFBFC` | 右侧面板背景 |
| `bg-hover` | `#F0F0F2` | Hover |
| `bg-selected` | `#E8E8EC` | Selected |
| `bg-active` | `#EDEFFB` | 激活态辅助底色 |
| `text-primary` | `#1D1D1F` | 主文字 |
| `text-secondary` | `#6E6E73` | 次文字 |
| `text-tertiary` | `#AEAEB2` | 提示文字 |
| `accent` | `#3B82F6` | 主强调色 |
| `shadow-soft` | `rgba(15, 23, 42, 0.08)` | 轻阴影 |

#### Dark Mode

| Token | 值 | 用途 |
|-------|-----|------|
| `bg-sidebar` | `#1C1C1E` | 左侧导航背景 |
| `bg-chrome` | `#2C2C2E` | 顶部工具区 / Tab 区 |
| `bg-content` | `#1E1E1E` | 内容背景 |
| `bg-panel` | `#252527` | 右侧面板背景 |
| `bg-hover` | `#3A3A3C` | Hover |
| `bg-selected` | `#48484A` | Selected |
| `bg-active` | `#243246` | 激活态辅助底色 |
| `text-primary` | `#F5F5F7` | 主文字 |
| `text-secondary` | `#8E8E93` | 次文字 |
| `text-tertiary` | `#636366` | 提示文字 |
| `accent` | `#64A4FF` | 主强调色 |
| `shadow-soft` | `rgba(0, 0, 0, 0.28)` | 轻阴影 |

### 4.3 间距系统

| Token | 值 |
|-------|-----|
| `space-xs` | 4px |
| `space-sm` | 8px |
| `space-md` | 12px |
| `space-lg` | 16px |
| `space-xl` | 24px |
| `space-2xl` | 32px |
| `space-3xl` | 48px |

### 4.4 圆角系统

| 元素 | Radius |
|------|--------|
| 小型 hover 底 | 6px |
| Tab / List Item / Input | 8px |
| 卡片 / 代码块 / Panel 内组件 | 10px |
| Dialog / Sheet | 12px |
| Pill Button | 18px |
| 浮层大卡片 | 20px |

---

## 5. 组件规范

### 5.1 顶部工具区

顶部工具区不采用完全浮空的悬浮按钮组，而采用稳定窗口工具区。

布局建议：

- 左：侧边栏开关、返回、前进
- 中：路径标题 / 当前文档名 / 面包屑
- 右：搜索、分享、评论、布局切换、更多操作

规则：

- 高度 `44px`
- 背景 `bg-chrome`
- 与内容区之间仅用色差区分
- 右侧主要按钮为图标按钮，分享可带文字

### 5.2 Tab 栏

- 高度 `38px`
- 背景 `bg-chrome`
- 当前项使用 `bg-content` 胶囊，不使用底部蓝线
- Hover 使用 `bg-hover`
- `padding: 6px 12px`
- `max-width: 180px`
- 图标 `12px`
- 标题 `12px`
- 关闭按钮默认弱显，仅 hover 或 active 时显示

Tab 的目标是弱存在感，不要抢主文档层级。

### 5.3 左侧导航栏

- 默认宽度 `240px`
- 可拖拽范围 `200px - 320px`
- 背景 `bg-sidebar`
- 项高度 `32px` 到 `36px`
- 选中态使用圆角底，不使用左侧色条

组成：

1. Space Switcher
2. 搜索输入框
3. 顶层导航入口
4. 文件夹与文档树
5. 底部工具区

搜索框：

- 高度 `32px`
- 内嵌在顶部
- 背景 `bg-hover`
- Radius `8px`

底部工具区建议保留：

- Settings
- Help
- Sync / Status

### 5.4 中央内容区

内容区不要“过松”。需要兼顾可读性和编辑效率。

编辑模式：

- 内容最大宽度 `760px - 840px`
- 页面左右 padding `40px - 56px`
- 默认字号 `15px`
- 默认行高 `1.5 - 1.6`

预览模式：

- 与编辑模式共享相同宽度体系
- 不额外增加巨大留白

空文档状态：

- 展示标题输入
- 展示轻量提示
- 展示可插入内容入口

### 5.5 右侧上下文面板

- 默认宽度 `280px`
- 可扩展到 `360px`
- 背景 `bg-panel`
- 面板头部固定
- 主体内容滚动

面板切换策略：

- 切换面板时替换内容，不叠多个抽屉
- 面板切换动画 `150ms ease-out`

### 5.6 按钮

Primary：

- `accent` 背景
- 白字
- Radius `18px`
- Padding `8px 16px`

Secondary：

- `bg-hover` 背景
- `text-primary`
- Hover 到 `bg-selected`

Ghost：

- 透明背景
- Hover 出现 `bg-hover`
- 常用于工具区和块操作

---

## 6. 状态与反馈

### 6.1 Hover

只给可操作对象反馈，不让整个界面持续闪烁。

规则：

- 块 hover 时显示手柄和更多按钮
- 侧边栏项 hover 时显示弱底色
- 工具按钮 hover 时显示最小包围底

### 6.2 Selected

Selected 需要比 Hover 更明确，但仍然克制。

规则：

- 使用 `bg-selected`
- 必要时叠加轻描边或内阴影
- 避免高饱和蓝色铺底

### 6.3 Focus

编辑焦点是一级状态。

规则：

- 当前编辑块可有弱强调边界或背景
- 焦点移动不应引发整页布局抖动
- 焦点模式下收缩周边噪音

### 6.4 Empty / Loading / Error

这些状态必须写入规范，而不是开发时临时补。

要求：

- Empty 状态给出下一步行动
- Loading 使用骨架屏或轻占位
- Error 给出恢复动作

---

## 7. 动效规范

| 场景 | 时长 | 曲线 |
|------|------|------|
| Hover 背景出现 | 100ms | ease-out |
| Tab 切换 | 150ms | ease-out |
| 面板切换 | 150ms | ease-out |
| 文件夹展开 | 180ms | ease-out |
| Command Palette 出现 | 140ms | ease-out |
| Focus Mode 进入/退出 | 180ms | ease-out |
| Modal / Sheet 弹出 | 220ms | ease-out |

原则：

- 不用花哨弹簧动画
- 不让动效影响编辑效率
- 动效只服务于状态理解

---

## 8. 键盘优先规范

必须定义，不作为后续增强项。

核心快捷键建议：

- `Cmd/Ctrl + P`: Quick Open / Command Palette
- `/`: Slash Command
- `Cmd/Ctrl + K`: 插入 Markdown 链接
- `Cmd/Ctrl + F`: 当前文档查找
- `Cmd/Ctrl + Shift + F`: 打开右侧全局搜索
- `Option + Cmd/Ctrl + B`: 切换左侧栏
- `Esc`: 退出当前浮层或收起面板

键盘交互原则：

- 所有关键浮层都必须可完整键盘操作
- 选中状态必须支持方向键扩展
- 右侧面板中的列表也要支持键盘导航

---

## 9. 与 v2 的关键调整

| v2 | v3 调整 |
|----|---------|
| 重点在颜色、圆角、toolbar 外观 | 补足信息架构和交互骨架 |
| 右上角浮动 pill 工具栏 | 改为稳定窗口工具区 |
| 侧边栏更像单纯文件树 | 改为分层导航系统 |
| 内容区偏写作工具排版 | 调整为兼顾阅读和块编辑效率 |
| 缺少右侧面板定义 | 明确 Insert / Style / Info / Comments / Share |
| 缺少命令模型 | 强化 Slash Command、Quick Open、全局搜索 |
| 缺少块级状态定义 | 明确 Hover / Selected / Focus / 多选 |

---

## 10. 本地 Craft 检查结论

检查对象：

- `/Applications/Craft.app`
- 版本 `3.4.4`
- bundle id `com.lukilabs.lukiapp`

结构结论：

- Craft 使用 `Craft.AppShell_CraftAppShell.bundle`、`Craft.BlockEditor_CraftBlockEditor.bundle`、`Craft.InsertPanel_CraftInsertPanel.bundle`、`Craft.SharePanel_CraftSharePanel.bundle`、`Craft.ThemeUI_CraftThemeUI.bundle`、`Craft.UICore_CraftUICore.bundle` 等模块化资源包
- 二进制符号显示交互核心包含 `LukiWindowToolBar`、`LukiWindowTabBar`、`LukiWindowRightSideBarState`、`FocusMode`
- 命令系统包含 `v2CommandMenu`、`v2CommandMenuList`、`CommandMenuDocumentPreviewView`
- 右侧上下文系统包含 `v2BlockDetailsMacSideControls`、`v2BlockDetailsMacSideControlButton`、`v2BlockDetailsMacSideControlsPanelType`、`v2BlockDetailsMacSideControlsPinnedState`
- 面板命名直接对应 `InsertPanel`、`StylePanel`、`PageInfoPanel`、`ThemePanel`、`OrganizePanel`、`SharePanel`、`LukiRightSidebarView`、`LukiRightSideBarAllCommentsView`

设计推论：

- Craft 的核心不是一个漂亮 toolbar，而是稳定 App Shell、Block Editor、Command Menu、右侧 Side Controls/Panel 的组合
- MEditor 应优先复刻这种信息架构和交互分层，而不是复制 Craft 视觉资产或私有实现
- 当前 v3 的 `AppShell + RightPanelRail + RightPanelHost + CommandPalette + Slash expansion` 是正确的中间态

---

## 11. 实施优先级

### Phase 1

- 重做主窗口层级
- 调整左侧导航和 Tab 样式
- 重做顶部工具区
- 调整内容区宽度、字号、间距

### Phase 2

- 落右侧面板系统
- 落 Slash Command
- 落 Quick Open
- 落文档内搜索和全局搜索

### Phase 3

- 完整块级 hover / selection / multi-select
- Focus Mode
- 动效和状态补齐
- 深色模式精修

---

## 12. 设计验收标准

以下问题如果回答为“否”，则设计未完成：

1. 用户能否只靠键盘完成打开文档、插入块、切换面板、搜索？
2. 左侧导航是否表达清楚“空间、集合、文档树”的层级？
3. 右侧面板是否成为稳定的上下文系统，而不是零散弹层？
4. 块在 Hover、Selected、Focus 下是否具有明确且克制的反馈？
5. 主文档区是否在阅读和编辑之间取得平衡，而不是过松或过挤？
6. 界面层次是否主要通过背景和间距建立，而不是边框堆出来？
