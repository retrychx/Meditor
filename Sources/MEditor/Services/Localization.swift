import Foundation
import Observation

/// UI language options. `.system` follows the OS preferred language.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, english, chinese
    var id: String { rawValue }
}

/// Runtime UI localization. `@Observable` so any SwiftUI view that calls
/// `L(...)` in its body re-renders when the language changes — no relaunch
/// needed for in-window UI. (The main menu bar refreshes on next launch.)
@Observable
final class LocalizationManager {
    static let shared = LocalizationManager()
    private static let key = "MEditor.language"

    var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: Self.key) }
    }

    private init() {
        if let raw = UserDefaults.standard.string(forKey: Self.key),
           let lang = AppLanguage(rawValue: raw) {
            language = lang
        } else {
            language = .system
        }
    }

    /// Effective language after resolving `.system`.
    var resolved: AppLanguage {
        guard language == .system else { return language }
        let prefersZh = Locale.preferredLanguages.first?.hasPrefix("zh") ?? false
        return prefersZh ? .chinese : .english
    }

    func localized(_ key: String) -> String {
        // Reading `resolved` (which reads `language`) registers the dependency.
        let useZh = (resolved == .chinese)
        guard let pair = Self.table[key] else { return key }
        return useZh ? pair.zh : pair.en
    }
}

/// Look up a localized string by key.
func L(_ key: String) -> String { LocalizationManager.shared.localized(key) }

/// Look up a localized format string and interpolate arguments.
func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: LocalizationManager.shared.localized(key), arguments: args)
}

// MARK: - Translation table

extension LocalizationManager {
    static let table: [String: (en: String, zh: String)] = [
        // Common
        "common.ok": ("OK", "好"),
        "common.cancel": ("Cancel", "取消"),
        "common.save": ("Save", "保存"),
        "common.create": ("Create", "创建"),
        "common.delete": ("Delete", "删除"),
        "common.close": ("Close", "关闭"),
        "common.yes": ("Yes", "是"),
        "common.no": ("No", "否"),
        "common.search": ("Search", "搜索"),
        "common.noMatches": ("No matches", "无匹配项"),

        // Menus / commands
        "menu.openFolder": ("Open Folder…", "打开文件夹…"),
        "menu.openFile": ("Open File…", "打开文件…"),
        "menu.newFile": ("New from Template…", "从模板新建…"),
        "menu.saveAsTemplate": ("Save as Template…", "保存为模板…"),
        "template.search": ("Search templates…", "搜索模板…"),
        "template.myTemplates": ("My Templates", "我的模板"),
        "template.create": ("Create", "创建"),
        "template.saveTitle": ("Save as Template", "保存为模板"),
        "template.namePlaceholder": ("Template name", "模板名称"),
        "template.saveMessage": ("Save current file content as a reusable template.", "将当前文件内容保存为可复用模板。"),
        "template.builtinSection": ("Built-in", "内置模板"),
        "template.blank": ("Blank", "空白文档"),
        "template.blankDesc": ("Empty document", "空文档"),
        "template.meeting": ("Meeting Notes", "会议记录"),
        "template.meetingDesc": ("Attendees, agenda, action items", "参会人、议程、待办事项"),
        "template.techDesign": ("Tech Design", "技术方案"),
        "template.techDesignDesc": ("Background, design, implementation plan", "背景、设计、实施计划"),
        "template.weekly": ("Weekly Report", "周报"),
        "template.weeklyDesc": ("Progress, blockers, next week plan", "进展、阻塞、下周计划"),
        "template.journal": ("Journal", "日记"),
        "template.journalDesc": ("Daily reflection and notes", "每日反思与笔记"),
        "template.htmlDoc": ("HTML Document", "HTML 文档"),
        "template.htmlDocDesc": ("Styled document with sidebar navigation", "带侧边栏导航的样式文档"),
        "menu.newFolder": ("New Folder", "新建文件夹"),
        "menu.save": ("Save", "保存"),
        "menu.find": ("Find…", "查找…"),
        "menu.findNext": ("Find Next", "查找下一个"),
        "menu.findPrevious": ("Find Previous", "查找上一个"),
        "menu.useSelectionForFind": ("Use Selection for Find", "用所选内容查找"),
        "menu.jumpToLine": ("Jump to Line…", "跳转到行…"),
        "menu.replace": ("Replace…", "替换…"),
        "menu.closeTab": ("Close Tab", "关闭标签"),
        "menu.reopenClosedTab": ("Reopen Closed Tab", "重新打开关闭的标签"),
        "menu.nextTab": ("Next Tab", "下一个标签"),
        "menu.previousTab": ("Previous Tab", "上一个标签"),
        "menu.quickOpen": ("Quick Open…", "快速打开…"),
        "menu.commandPalette": ("Command Palette…", "命令面板…"),
        "menu.copyAbsolutePath": ("Copy Absolute Path", "复制绝对路径"),
        "menu.copyRelativePath": ("Copy Relative Path", "复制相对路径"),
        "menu.revealInFinder": ("Reveal in Finder", "在 Finder 中显示"),
        "panel.chooseFolder": ("Choose a project folder", "选择一个项目文件夹"),

        // Welcome
        "welcome.subtitle": ("Markdown & HTML Editor", "Markdown & HTML 编辑器"),
        "welcome.dropHint": ("Or drop a folder here", "或将文件夹拖放到此处"),

        // Alerts
        "alert.errorTitle": ("Error", "错误"),
        "alert.saveChangesTitle": ("Save changes?", "保存更改？"),
        "alert.dontSave": ("Don't Save", "不保存"),
        "alert.saveChangesMessage": ("Save changes to \"%@\" before closing?", "关闭前保存对“%@”的更改？"),

        // Toolbar tooltips
        "tooltip.showSidebar": ("Show Sidebar (⌥⌘B)", "显示侧边栏 (⌥⌘B)"),
        "tooltip.hideSidebar": ("Hide Sidebar (⌥⌘B)", "隐藏侧边栏 (⌥⌘B)"),
        "tooltip.showPreview": ("Show Preview (⌘⇧V)", "显示预览 (⌘⇧V)"),
        "tooltip.hidePreview": ("Hide Preview (⌘⇧V)", "隐藏预览 (⌘⇧V)"),
        "tooltip.showEditor": ("Show Editor (⌘⇧M)", "显示编辑器 (⌘⇧M)"),
        "tooltip.hideEditor": ("Hide Editor (⌘⇧M)", "隐藏编辑器 (⌘⇧M)"),
        "tooltip.focusMode": ("Focus Mode", "专注模式"),
        "tooltip.exitFocus": ("Exit Focus Mode (Esc)", "退出专注模式 (Esc)"),
        "focus.hint": ("Press Esc to exit Focus Mode", "按 Esc 退出专注模式"),

        // Sharing
        "share.viaLAN": ("Share via LAN", "通过局域网分享"),
        "share.stopWithURL": ("Stop Sharing (%@)", "停止分享 (%@)"),
        "share.active": ("LAN Share Active", "局域网分享中"),
        "share.currentFile": ("Current file:", "当前文件："),
        "share.copyURL": ("Copy URL", "复制链接"),
        "share.stop": ("Stop Sharing", "停止分享"),

        // Export
        "export.title": ("Export Preview", "导出预览"),
        "export.markdown": ("Export as Markdown…", "导出为 Markdown…"),
        "export.pdf": ("Export as PDF…", "导出为 PDF…"),
        "export.image": ("Export as Image…", "导出为图片…"),
        "export.html": ("Export as HTML…", "导出为 HTML…"),

        // Theme
        "theme.title": ("Preview Theme", "预览主题"),

        // Quick Open
        "quickOpen.placeholder": ("Open file by name…", "按名称打开文件…"),
        "quickOpen.commandPlaceholder": ("Search files and actions…", "搜索文件和操作…"),
        "quickOpen.typeToSearch": ("Type to search files", "输入以搜索文件"),
        "quickOpen.actions": ("Actions", "操作"),
        "quickOpen.files": ("Files", "文件"),
        "quickOpen.toggleFocusMode": ("Toggle Focus Mode", "切换专注模式"),
        "quickOpen.toggleFocusModeDesc": ("Hide surrounding panels and keep the document frontmost", "隐藏周边面板，让文档保持在前景"),
        "quickOpen.toggleSidebar": ("Toggle Sidebar", "切换侧边栏"),
        "quickOpen.toggleSidebarDesc": ("Show or hide the file sidebar", "显示或隐藏文件侧边栏"),
        "quickOpen.toggleEditor": ("Toggle Editor", "切换编辑器"),
        "quickOpen.toggleEditorDesc": ("Show or hide the editor pane", "显示或隐藏编辑器面板"),
        "quickOpen.togglePreview": ("Toggle Preview", "切换预览"),
        "quickOpen.togglePreviewDesc": ("Show or hide the preview pane", "显示或隐藏预览面板"),
        "quickOpen.openInsertPanel": ("Open Insert Panel", "打开插入面板"),
        "quickOpen.openInsertPanelDesc": ("Create documents and reusable templates", "创建文档和可复用模板"),
        "quickOpen.openStylePanel": ("Open Style Panel", "打开样式面板"),
        "quickOpen.openStylePanelDesc": ("Change theme and workspace layout", "调整主题和工作区布局"),
        "quickOpen.openPageInfo": ("Open Page Info", "打开页面信息"),
        "quickOpen.openPageInfoDesc": ("Show metadata for the current document", "显示当前文档的元信息"),
        "quickOpen.openComments": ("Open Comments", "打开评论"),
        "quickOpen.openCommentsDesc": ("Show the document comments panel", "显示文档评论面板"),
        "quickOpen.openSharePanel": ("Open Share Panel", "打开分享面板"),
        "quickOpen.openSharePanelDesc": ("Manage LAN sharing from the right panel", "在右侧面板管理局域网分享"),
        "quickOpen.openSearchResults": ("Open Search Results", "打开搜索结果"),
        "quickOpen.openSearchResultsDesc": ("Show the global search results panel", "显示全局搜索结果面板"),
        "quickOpen.openOutlinePanel": ("Open Outline Panel", "打开大纲面板"),
        "quickOpen.openOutlinePanelDesc": ("Jump between Markdown headings from the right panel", "从右侧面板跳转 Markdown 标题"),
        "quickOpen.openFolder": ("Open Folder…", "打开文件夹…"),
        "quickOpen.openFolderDesc": ("Choose another workspace folder", "选择另一个工作区文件夹"),
        "quickOpen.newDocument": ("New from Template…", "从模板新建…"),
        "quickOpen.newDocumentDesc": ("Create a document in the current workspace", "在当前工作区中创建文档"),
        "quickOpen.cycleTheme": ("Cycle Theme", "切换主题"),
        "quickOpen.cycleThemeDesc": ("Switch to the next preview theme", "切换到下一个预览主题"),
        "quickOpen.exportPDF": ("Export as PDF…", "导出为 PDF…"),
        "quickOpen.exportPDFDesc": ("Export the current preview as PDF", "将当前预览导出为 PDF"),

        // Right panel
        "rightPanel.insert": ("Insert", "插入"),
        "rightPanel.style": ("Style", "样式"),
        "rightPanel.outline": ("Outline", "大纲"),
        "rightPanel.pageInfo": ("Page Info", "页面信息"),
        "rightPanel.comments": ("Comments", "评论"),
        "rightPanel.share": ("Share", "分享"),
        "rightPanel.search": ("Search Results", "搜索结果"),
        "rightPanel.outline.previewNote": ("The preview outline is still shown beside Markdown preview. This panel is reserved for the unified document outline.", "Markdown 预览旁仍显示大纲。此面板将作为统一文档大纲入口。"),
        "rightPanel.outline.emptyTitle": ("No outline", "暂无大纲"),
        "rightPanel.outline.emptyMessage": ("Open a Markdown document to inspect its heading structure.", "打开 Markdown 文档以查看标题结构。"),
        "rightPanel.info.name": ("Name", "名称"),
        "rightPanel.info.path": ("Path", "路径"),
        "rightPanel.info.language": ("Language", "语言"),
        "rightPanel.info.size": ("Size", "大小"),
        "rightPanel.info.words": ("Words", "词数"),
        "rightPanel.info.modified": ("Modified", "已修改"),
        "rightPanel.info.emptyTitle": ("No document selected", "未选择文档"),
        "rightPanel.info.emptyMessage": ("Open a file to see document details.", "打开文件后可查看文档详情。"),
        "rightPanel.comments.emptyTitle": ("No comments yet", "暂无评论"),
        "rightPanel.comments.emptyMessage": ("Add document-level notes here. They are stored locally and stay out of the Markdown file.", "在这里添加文档级备注。内容会保存在本地，不写入 Markdown 文件。"),
        "rightPanel.comments.noDocumentTitle": ("No document selected", "未选择文档"),
        "rightPanel.comments.noDocumentMessage": ("Open a file to add document comments.", "打开文件后可添加文档评论。"),
        "rightPanel.comments.add": ("New Comment", "新评论"),
        "rightPanel.comments.addButton": ("Add Comment", "添加评论"),
        "rightPanel.comments.markResolved": ("Mark Resolved", "标记为已解决"),
        "rightPanel.comments.markOpen": ("Mark Open", "标记为未解决"),
        "rightPanel.search.emptyTitle": ("No search yet", "尚未搜索"),
        "rightPanel.search.emptyMessage": ("Global search results will appear here so they do not compete with Quick Open.", "全局搜索结果将显示在这里，避免与快速打开混在一起。"),
        "rightPanel.search.placeholder": ("Search files and content…", "搜索文件和内容…"),
        "rightPanel.search.noMatchesMessage": ("Try another file name, path, or content query.", "试试其他文件名、路径或正文关键词。"),
        "rightPanel.search.recent": ("Recent", "最近"),
        "rightPanel.search.files": ("Files", "文件"),
        "rightPanel.search.content": ("Content", "内容"),
        "rightPanel.search.scanning": ("Scanning file contents…", "正在扫描文件内容…"),
        "rightPanel.share.message": ("Start LAN sharing to make currently open documents available on the local network.", "启动局域网分享后，可在本地网络访问当前打开的文档。"),
        "rightPanel.insert.message": ("Use existing document creation tools from a stable side panel while editing.", "编辑时可从稳定的侧边面板使用现有文档创建工具。"),

        // Sidebar
        "sidebar.search": ("Search", "搜索"),
        "sidebar.newDocument": ("New Document", "新建文档"),
        "sidebar.allDocs": ("All Docs", "所有文档"),
        "sidebar.recent": ("Recent", "最近"),
        "sidebar.tasks": ("Tasks", "任务"),
        "sidebar.calendar": ("Calendar", "日历"),
        "sidebar.imagine": ("Imagine", "Imagine"),
        "sidebar.sharedWithMe": ("Shared with Me", "与我共享"),
        "sidebar.favorites": ("Favorites", "收藏"),
        "sidebar.favoritesHint": ("Favorite docs for quick access", "收藏文档以便快速访问"),
        "sidebar.folders": ("Folders", "文件夹"),
        "sidebar.tags": ("Tags", "标签"),
        "sidebar.tagsHint": ("Pin keywords here for quick access", "固定关键词标签以便快速访问"),
        "sidebar.newFolder": ("New Folder", "新建文件夹"),
        "menu.preferences": ("Preferences", "偏好设置"),
        "create.folderName": ("Folder name", "文件夹名称"),
        "create.fileName": ("File name", "文件名称"),
        "create.messageFolder": ("Enter a name for the new folder.", "请输入新文件夹的名称。"),
        "create.messageFile": ("Enter a name for the new file.", "请输入新文件的名称。"),
        "rename.title": ("Rename", "重命名"),
        "rename.newName": ("New name", "新名称"),
        "rename.messageFormat": ("Rename “%@” to:", "将“%@”重命名为："),
        "delete.confirmFormat": ("Are you sure you want to delete “%@”?", "确定要删除“%@”吗？"),
        "error.createFolderFailed": ("Failed to create folder: %@", "创建文件夹失败：%@"),
        "error.createFileFailed": ("Failed to create file: %@", "创建文件失败：%@"),
        "error.renameFailed": ("Failed to rename: %@", "重命名失败：%@"),
        "error.deleteFailed": ("Failed to delete: %@", "删除失败：%@"),

        // Tab context menu
        "tab.close": ("Close", "关闭"),
        "tab.closeOthers": ("Close Others", "关闭其他"),
        "tab.closeAll": ("Close All", "关闭全部"),
        "tab.showInFinder": ("Show in Finder", "在 Finder 中显示"),

        // Editor / Preview placeholders
        "editor.selectFile": ("Select a file to edit", "选择一个文件进行编辑"),
        "preview.empty": ("Preview", "预览"),
        "preview.findPlaceholder": ("Find in Preview", "在预览中查找"),
        "preview.findNoResults": ("No results", "无结果"),

        // Settings
        "settings.tab.general": ("General", "通用"),
        "settings.tab.editor": ("Editor", "编辑器"),
        "settings.tab.sharing": ("Sharing", "分享"),
        "settings.section.preview": ("Preview", "预览"),
        "settings.fontSize": ("Font Size", "字体大小"),
        "settings.section.save": ("Save", "保存"),
        "settings.autoSave": ("Auto-Save", "自动保存"),
        "settings.interval": ("Interval", "间隔"),
        "settings.secondsFormat": ("%d sec", "%d 秒"),
        "settings.section.launchLayout": ("Default Layout on Launch", "启动时默认布局"),
        "settings.showSidebar": ("Show Sidebar", "显示侧边栏"),
        "settings.showEditor": ("Show Editor", "显示编辑器"),
        "settings.showPreview": ("Show Preview", "显示预览"),
        "settings.section.lanShare": ("LAN Sharing", "局域网分享"),
        "settings.port": ("Port", "端口"),
        "settings.portHint": ("Port used for LAN preview sharing, default 8899", "局域网预览分享使用的端口，默认 8899"),
        "settings.section.language": ("Language", "语言"),
        "settings.language": ("Language", "语言"),
        "lang.system": ("System", "跟随系统"),

        // AppError descriptions
        "error.openFailed": ("Couldn't open “%@”: %@", "无法打开“%@”：%@"),
        "error.saveFailed": ("Couldn't save “%@”: %@", "无法保存“%@”：%@"),
        "error.deleteFailed2": ("Couldn't delete “%@”: %@", "无法删除“%@”：%@"),
        "error.renameFailed2": ("Couldn't rename “%@”: %@", "无法重命名“%@”：%@"),
        "error.createFailed": ("Couldn't create “%@”: %@", "无法创建“%@”：%@"),
        "error.accessDenied": ("Access denied to “%@”.", "无权访问“%@”。"),
        "error.previewResourceMissing": ("Preview resource missing: %@.", "缺少预览资源：%@。"),
        "error.exportFailed": ("Export to %@ failed: %@.", "导出为 %@ 失败：%@。"),
        "error.unknown": ("unknown error", "未知错误"),
        "error.sessionRestoreFailed": ("Couldn't restore previous session: %@.", "无法恢复上次会话：%@。"),

        // Export errors
        "export.err.noWebView": ("Preview is not available.", "预览不可用。"),
        "export.err.js": ("Export failed (JS): %@", "导出失败（JS）：%@"),
        "export.err.pdf": ("PDF export failed: %@", "PDF 导出失败：%@"),
        "export.err.image": ("Image export failed: %@", "图片导出失败：%@"),
    ]
}
