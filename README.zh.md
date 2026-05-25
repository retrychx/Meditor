<p align="center">
  <img src="assets/icon.png" width="128" alt="MEditor 图标" />
</p>

<h1 align="center">MEditor</h1>

<p align="center">
  <strong>基于 SwiftUI 的原生 macOS Markdown & HTML 编辑器</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14.0+-blue?logo=apple" alt="macOS 14+" />
  <img src="https://img.shields.io/badge/Swift-5.9-orange?logo=swift" alt="Swift 5.9" />
  <img src="https://img.shields.io/badge/%E5%8D%8F%E8%AE%AE-MIT-green" alt="MIT License" />
  <img src="https://img.shields.io/badge/%E7%BC%96%E8%AF%91-%E9%80%9A%E8%BF%87-brightgreen" alt="编译通过" />
</p>

<p align="center">
  🌐 <strong>中文</strong> | <a href="README.md"><strong>English</strong></a>
</p>

---

## ✨ 功能特性

- **📝 实时预览** — 基于 marked.js 的 Markdown 渲染，highlight.js 代码高亮，Mermaid.js 图表支持
- **🎨 语法高亮** — 编辑器（原生 `NSTextView`）和预览区均支持 40+ 语言，含完整的别名映射（`shell`→`bash`，`ts`→`typescript` 等）
- **🔀 双向滚动同步** — 编辑器和预览区滚动互相同步，带防循环保护
- **📂 文件浏览器** — 侧栏支持搜索、右键菜单（新建文件/文件夹、重命名、删除、在 Finder 中显示）
- **📁 文件树自动刷新** — 基于 FSEvents 的文件监控，外部修改即时反映
- **📑 标签页管理** — 拖拽排序、关闭确认（保存/不保存/取消）
- **🔄 面板拖拽缩放** — 侧栏、编辑器、预览区均可拖拽调整宽度（1px 视觉线 + 6px 手势热区）
- **📊 状态栏** — 光标位置（Ln/Col）、文件大小、UTF-8 编码指示
- **🌙 深色模式** — 完整支持 macOS 深色/浅色模式自适应
- **💻 原生体验** — 纯 SwiftUI + AppKit，无 Electron 依赖，轻量高效

## 📋 系统要求

- **macOS** 14.0+ (Sonoma)
- **Xcode** 15.0+（开发用）
- **Swift** 5.9+

## 🔧 构建与运行

### 快速启动

```bash
# 克隆仓库
git clone https://github.com/retrychx/Meditor.git
cd Meditor

# 使用 SPM 构建
swift build

# 直接运行（轻量模式，无应用图标）
swift run
```

### 生成 .app 包

```bash
# 构建后打包为 .app
swift build
bash scripts/bundle.sh

# 启动（带图标、Dock 驻留、文档类型关联）
open .build/debug/MEditor.app
```

> **注意：** `bundle.sh` 会自动对 `.app` 包进行 ad-hoc 签名。打开一次后，即可在任意 `.md` 或 `.html` 文件上使用 **显示简介 → 打开方式 → MEditor → 全部更改** 来关联文件类型。

### 在 Xcode 中打开

```bash
open Package.swift
```

---

## 🏗 项目结构

```
MEditor/
├── Package.swift                # SPM 配置文件
├── scripts/
│   └── bundle.sh                # .app 包组装脚本
├── docs/
│   └── code-review-and-roadmap.zh.md  # 代码质量分析 & 功能路线图
└── Sources/MEditor/
    ├── MEditorApp.swift         # 应用入口 & @main 结构体
    ├── Info.plist               # 应用配置 & 文档类型关联
    ├── Models/
    │   ├── EditorTab.swift      # 标签模型（路径、内容、语言、修改标记）
    │   └── FileItem.swift       # 文件树节点（路径、目录标记、子节点）
    ├── Protocols/
    │   ├── FileServiceProtocol.swift      # 文件 I/O 抽象
    │   └── SyntaxHighlightEngine.swift    # 语法高亮抽象
    ├── Resources/
    │   ├── AppIcon.icns         # 应用图标（全分辨率）
    │   └── Preview/             # 本地 JS 库（无需网络请求）
    │       ├── marked.min.js    # Markdown → HTML 渲染器
    │       ├── highlight.min.js # 代码语法高亮器
    │       └── mermaid.min.js   # 图表渲染器（流程图、时序图等）
    ├── Services/
    │   ├── FileService.swift              # 文件 I/O 实现
    │   ├── FileWatcherService.swift       # FSEvents 目录监控
    │   ├── FileTypeConfiguration.swift    # 文件类型注册表（图标、颜色、语言）
    │   ├── HTMLHighlightEngine.swift      # 基于正则的 HTML 高亮
    │   ├── HighlightService.swift         # 高亮引擎注册表
    │   └── MarkdownHighlightEngine.swift  # 基于正则的 Markdown 高亮
    ├── ViewModels/
    │   └── AppState.swift       # 全局可观察状态（@Observable macro）
    └── Views/
        ├── ContentView.swift    # 根布局（欢迎页 + 主界面）
        ├── Editor/
        │   ├── EditorTabBar.swift       # 可拖拽排序的标签栏
        │   ├── EditorView.swift         # 编辑器容器
        │   └── NativeEditorView.swift   # NSTextView 封装 + 语法高亮
        ├── Preview/
        │   ├── MarkdownWebPreview.swift # WKWebView Markdown 渲染
        │   ├── PreviewPanel.swift       # 预览容器
        │   └── WebPreviewView.swift     # WKWebView 原始 HTML
        ├── Shared/
        │   ├── PanelLabel.swift         # 可复用的面板标题
        │   └── VisualEffect.swift       # NSVisualEffectView 封装
        └── Sidebar/
            ├── FileRow.swift            # 文件行 + 右键菜单
            └── FileSidebar.swift        # 文件树 + 搜索 + 增删改查
```

---

## 🔍 代码质量与路线图

详见 [`docs/code-review-and-roadmap.zh.md`](docs/code-review-and-roadmap.zh.md)（中文完整版）。

简要评价：

| 方面 | 评价 |
|------|------|
| **架构设计** | ⭐ 面向协议 + 清晰的 Service 层 |
| **性能优化** | ⭐ 大文件阈值（500KB）、操作防抖 |
| **安全性** | ⭐ JSON 编码预览、CSP 安全头 |
| **待改进** | 🔧 HTML 模板嵌入在 Swift 字符串中 |
| **待改进** | 🔧 资源复制代码冗余 |
| **即将开发** | 偏好设置窗口、字体配置、会话恢复 |

### 路线图概要

**P1（优先）**
- [x] 应用图标
- [x] 文档类型关联
- [ ] 编辑器字体/字号设置
- [ ] 偏好设置窗口
- [ ] 自动保存 + 会话恢复
- [ ] HTML 模板从 Swift 中抽离

**P2（体验增强）**
- [ ] Git 状态指示（侧栏文件旁显示 M/A/?）
- [ ] 全局搜索（⌘⇧F）
- [ ] 目录导航（Outline 面板）
- [ ] 图片粘贴/拖入
- [ ] 代码折叠

**P3（锦上添花）**
- [ ] 多窗口支持
- [ ] CSV/JSON 预览增强
- [ ] 打字机模式
- [ ] 导出 PDF/HTML

---

## 📄 开源协议

[MIT](LICENSE)

---

*用心打造 · 纯原生 macOS 体验*
