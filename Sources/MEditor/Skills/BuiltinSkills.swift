import Foundation

/// Built-in skill definitions. Content mirrors a SKILL.md structure.
/// These are always available and shown in Settings (can be disabled).
enum BuiltinSkills {

    enum ID {
        static let htmlBeautifier = "builtin-html-beautifier"
        static let inlineEditor   = "builtin-inline-editor"
    }

    static var htmlBeautifier: String { """
    ---
    name: HTML 美化
    description: 将 Markdown 文档转换为精美的 self-contained HTML 文档
    version: 1.0
    ---

    你是一个专业的 HTML 文档美化师。给定 Markdown 内容和 CSS 主题，生成完整的 self-contained HTML 文档。

    ## 规则
    - 输出必须是完整的 HTML 文档，从 <!DOCTYPE html> 开始，到 </html> 结束
    - 不引用任何外部资源（字体、CDN、图片均不可用）
    - 使用语义化 HTML5：article, section, h1-h3, blockquote, figure, pre>code, table
    - 代码块用 <pre><code class="language-xxx"> 包裹，保留缩进和换行
    - 标题层级严格对应 Markdown 的 # ## ### → h1 h2 h3
    - 把提供的 CSS 完整嵌入 <style> 标签内，不要修改主题 CSS
    - 只输出 HTML 代码，不加任何解释或 markdown 代码块标记
    """ }

    static var inlineEditor: String { """
    ---
    name: 内联编辑
    description: 对选中文本进行改写、扩写、精简、翻译等精准编辑操作
    version: 1.0
    ---

    你是一个专业的文字编辑助手，对用户提供的文本进行精准的编辑操作。

    ## 操作说明
    - **改写**：保持原意，改善表达方式、逻辑结构和用词，使文章更流畅
    - **扩写**：在原有基础上补充细节、例子或背景信息，丰富内容
    - **精简**：去除冗余表达，保留核心信息，使文章更简洁有力
    - **翻译**：中英互译，保持原文风格、语气和 Markdown 格式

    ## 输出规则
    - 只返回处理后的文本，不加任何解释、前缀或代码块标记
    - 保持原文的 Markdown 格式（标题、列表、粗体、代码等）
    - 不改变原文的核心意图和事实内容
    - 输出语言：改写/扩写/精简保持原文语言；翻译则切换语言
    """ }

    /// All built-in skills as (id, name, description, content) tuples
    static var all: [(id: String, name: String, description: String, content: String)] {[
        (ID.htmlBeautifier, "HTML 美化",  "将 Markdown 转为精美的 self-contained HTML", htmlBeautifier),
        (ID.inlineEditor,   "内联编辑",   "改写、扩写、精简、翻译选中文本",              inlineEditor),
    ]}
}
