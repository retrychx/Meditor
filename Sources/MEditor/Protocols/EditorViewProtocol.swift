import Foundation
import SwiftUI

/// 编辑器视图对外契约，与具体实现（NSTextView / UITextView）解耦。
///
/// macOS 实现：`NativeEditorView`（NSViewRepresentable → NSTextView）
/// iOS 实现（将来）：UIViewRepresentable → UITextView 版本
///
/// ## 设计说明
///
/// SwiftUI 的 `View` 协议通过关联类型 `Body` 做静态派发，无法直接用
/// `any EditorViewProtocol` 做类型擦除。因此本协议作为 **文档契约**
/// 存在，而非运行时多态接口：
///
/// - `NativeEditorView` 在注释层声明符合本协议（见文件顶部 MARK）。
/// - 将来新平台实现时，对照此协议补齐全部属性/回调即可无痛替换。
/// - AppState / AI 层只通过本协议列出的属性与编辑器交互，
///   不感知 NSTextView / NSScrollView 等 AppKit 类型。
///
/// ## 类型约束
///
/// 所有属性均使用 Foundation / SwiftUI 原生类型：
/// - `NSRange` → `Foundation.NSRange`（跨平台，非 AppKit 专属）
/// - `EditorLanguage` → 项目内 enum，无 AppKit 依赖
/// - `PreviewTheme` → 项目内 struct，提供跨平台色值
///
/// 禁止在此文件出现：`NSTextView`、`NSScrollView`、`NSFont`、
/// `NSAttributedString`、`AppKit`、`UIKit`。
protocol EditorViewProtocol: View {

    // MARK: - 内容

    /// 当前编辑器的完整文本内容。
    var content: String { get }

    /// 内容的单调递增版本号。外部（如切换 Tab / 文件重载）每次向编辑器
    /// 推送新内容时递增，让 `NSViewRepresentable.updateNSView` 能以
    /// O(1) 判断是否需要重置 `textView.string`，避免不必要的全文比对。
    var contentRevision: Int { get }

    /// 当前文件的语言类型，驱动语法高亮策略选择。
    var language: EditorLanguage { get }

    // MARK: - 回调（编辑器 → 外部）

    /// 用户键入或粘贴导致内容变化时调用，传出最新完整文本。
    var onContentChange: (String) -> Void { get }

    /// 光标移动时调用，参数为 (1-based 行号, 1-based 列号)。
    var onCursorChange: ((Int, Int) -> Void)? { get }

    /// 编辑器可视区域顶部行发生变化时调用，传出 0-based 行索引。
    /// 用于编辑器 → 预览的滚动同步。
    var onVisibleTopLineChange: ((Int) -> Void)? { get }

    /// 选区文字变化时调用，无选中时传空字符串。
    /// 供 AI 面板读取上下文。
    var onSelectionChange: ((String) -> Void)? { get }

    /// 选区的 `NSRange` 变化时调用。
    /// 用于在弹出 AI Sheet 前保存当前光标/选区位置，
    /// 以便 Sheet 关闭后能精准执行 Replace。
    var onRangeChange: ((NSRange) -> Void)? { get }

    // MARK: - 指令（外部 → 编辑器，输入驱动）

    /// 预览 → 编辑器滚动同步的目标行（0-based）。-1 表示无指令。
    var scrollToLine: Int { get }

    /// `scrollToLine` 的单调令牌，允许对同一行重复触发滚动。
    var scrollRequestID: Int { get }

    /// AI 面板发起的"在光标处插入"文本。
    var insertText: String { get }

    /// `insertText` 的单调令牌，允许重复插入相同文本。
    var insertRequestID: Int { get }

    /// InlineEdit 接受后的替换文本。
    var replaceText: String { get }

    /// `replaceText` 的单调令牌，允许重复替换相同文本。
    var replaceRequestID: Int { get }

    /// 要被替换的目标范围；`nil` 时使用编辑器当前选区。
    var pendingReplaceRange: NSRange? { get }

    // MARK: - 外观

    /// 当前主题，驱动编辑器背景色、前景色、插入点颜色。
    var theme: PreviewTheme { get }

    /// 编辑器字体大小（points）。
    var editorFontSize: Int { get }
}
