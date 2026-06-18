# MEditor UI Design Spec v2

参考：Craft（层次感 + 圆角 + 呼吸感）、Linear（极简 + 键盘优先）、Obsidian（文件树密度）

---

## 1. 设计原则

- **层次分明**：侧边栏 < Tab 栏 < 内容区，三层背景色递进
- **大圆角**：所有可交互元素 8-12px 圆角，按钮 pill 形
- **呼吸感**：行间距 36px+，不挤压
- **安静**：无边框分割线，用背景色差和阴影暗示层级
- **动效克制**：只在状态变化时用 150ms ease-out

---

## 2. 色彩系统

### Light Mode

| Token | 值 | 用途 |
|-------|-----|------|
| `bg-sidebar` | `#F5F5F7` | 侧边栏背景 |
| `bg-chrome` | `#FAFAFA` | Tab 栏背景 |
| `bg-content` | `#FFFFFF` | 编辑器 / 预览 |
| `bg-hover` | `#F0F0F2` | 悬停态 |
| `bg-selected` | `#E8E8EC` | 选中态（侧边栏 / tab） |
| `text-primary` | `#1D1D1F` | 主文字 |
| `text-secondary` | `#6E6E73` | 次要文字 |
| `text-tertiary` | `#AEAEB2` | 提示文字 |
| `accent` | `#3B82F6` | 强调色（极光蓝） |
| `border` | `#E5E5EA` | 极淡分割（几乎不用） |

### Dark Mode

| Token | 值 | 用途 |
|-------|-----|------|
| `bg-sidebar` | `#1C1C1E` | 侧边栏 |
| `bg-chrome` | `#2C2C2E` | Tab 栏 |
| `bg-content` | `#1E1E1E` | 内容区 |
| `bg-hover` | `#3A3A3C` | 悬停 |
| `bg-selected` | `#48484A` | 选中 |
| `text-primary` | `#F5F5F7` | 主文字 |
| `text-secondary` | `#8E8E93` | 次要 |
| `accent` | `#64A4FF` | 强调色 |

---

## 3. 间距系统

| Token | 值 | 用途 |
|-------|-----|------|
| `space-xs` | 4px | 图标与文字间距 |
| `space-sm` | 8px | 组件内部 padding |
| `space-md` | 12px | 列表项 vertical padding |
| `space-lg` | 16px | 区块间距 |
| `space-xl` | 24px | Section 间距 |

---

## 4. 组件规范

### 4.1 Tab 栏

```
高度：38px
背景：bg-chrome
Tab 样式：
  - 未选中：透明，text-secondary
  - 悬停：bg-hover 胶囊（radius 8px）
  - 选中：bg-content 胶囊 + 轻投影（0 1px 3px rgba(0,0,0,0.08)）
  - 无底部蓝线
Tab 内部：
  - 图标 12px + 文件名 12px + 关闭按钮 10px
  - padding: 6px 12px
  - max-width: 180px
新建 Tab 按钮：
  - "+" 图标，放在 tab 列表右侧
  - hover 时 bg-hover 圆形
```

### 4.2 侧边栏

```
宽度：240px（可拖拽 180-320px）
背景：bg-sidebar
行高：36px（icon + text + padding）
项目样式：
  - 未选中：透明
  - 悬停：bg-hover，radius 8px
  - 选中：bg-selected，radius 8px，text-primary 加粗
  - 无左侧指示条
图标：12px，text-tertiary
文字：13px，text-secondary
文件夹展开箭头：8px chevron，旋转 90° 动画
搜索框：
  - 顶部内嵌，radius 8px
  - 背景 bg-hover
  - placeholder text-tertiary
底部：
  - 小工具栏（设置齿轮 + 帮助），12px 图标
```

### 4.3 工具栏（右上角）

```
替代传统 toolbar，改为浮动按钮组：
  - pill 形按钮组（背景 bg-chrome，radius 20px，内含 2-3 个图标按钮）
  - 每个按钮 hover 有 bg-hover 圆形
  - 布局：[分享] [导出 | 主题 | 布局切换]
  - 分享按钮独立 pill（有文字"共享"）
```

### 4.4 内容区

```
背景：bg-content
编辑器：
  - 无边框
  - padding: 32px 48px（宽屏时 max-width: 800px 居中）
  - 字体：系统字体 15px，行高 1.7
预览：
  - 同编辑器 padding
  - 和编辑器之间无分割线，用 1px bg-border 或纯背景色差
```

### 4.5 按钮

```
Primary（创建/保存）：
  - accent 背景，白色文字
  - radius: 20px (pill)
  - padding: 8px 20px
  - hover: 加深 10%
  
Secondary：
  - bg-hover 背景，text-primary 文字
  - radius: 20px
  - hover: bg-selected

Ghost（工具栏）：
  - 透明背景
  - hover: bg-hover 圆形
  - 12-14px 图标
```

### 4.6 圆角规范

| 元素 | radius |
|------|--------|
| Tab 胶囊 | 8px |
| 侧边栏选中 | 8px |
| 搜索框 | 8px |
| 按钮 pill | 20px |
| 对话框 / Sheet | 12px |
| 代码块 | 8px |
| Tooltip | 6px |

---

## 5. 动效规范

| 场景 | 时长 | 曲线 |
|------|------|------|
| Hover 背景出现 | 100ms | ease-out |
| Tab 选中切换 | 150ms | ease-out |
| 文件夹展开 | 200ms | spring(0.3, 0.8) |
| Sheet 弹出 | 250ms | ease-out |
| 修改点消失 | 200ms | ease-out |

---

## 6. 与现在的主要差异

| 当前 | 改为 |
|------|------|
| Tab 底部蓝线 | 胶囊背景 + 投影 |
| 扁平分割线 | 背景色层次 |
| 紧凑行高 | 36px 呼吸感 |
| 普通 toolbar | pill 按钮组 |
| 搜索框无背景 | 灰底圆角搜索框 |
| 编辑器贴边 | 居中 + 大 padding |
