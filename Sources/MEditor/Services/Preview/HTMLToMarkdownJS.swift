import Foundation

/// HTML → Markdown 转换器（JS，DOM 递归）。导出（PreviewExporter）与粘贴
///（PasteHTMLConverter）共用同一份实现——转换规则只维护这里，两边行为
/// 永远一致。
///
/// 使用方式：在已加载目标 HTML 的 WKWebView 里先注入 `converterSource`
///（定义 `mdH2M(el, indent)`），再以 `mdH2M(rootEl, '')` 调用。
enum HTMLToMarkdownJS {

    /// 定义 `mdH2M(el, indent)`：把 DOM 子树转成 Markdown 文本。
    static let converterSource = """
    function mdH2M(el, indent) {
        indent = indent || '';
        var md = '';
        el.childNodes.forEach(function(node) {
            if (node.nodeType === 3) {
                // 折叠空白为单空格（模拟浏览器渲染）；纯空白节点（标签间的换行/缩进）
                // 直接丢弃，否则会作为前导空格污染行首，导致 ## 标题被当成代码块
                var t = node.textContent.replace(/\\s+/g, ' ');
                if (t.trim() !== '') md += t;
                return;
            }
            if (node.nodeType !== 1) return;
            var tag = node.tagName.toLowerCase();
            // 跳过脚本/样式/模板，避免 JS/CSS 源码混入 markdown
            if (tag === 'script' || tag === 'style' || tag === 'noscript' || tag === 'template') return;
            // 带 inline style 的元素保留为 raw HTML，但 <pre> 例外（走下方代码块转换更干净）；
            // 前后补空行，确保与相邻 markdown 块正确分隔，否则后续 ### 标题会紧贴而不渲染
            if (node.getAttribute('style') && tag !== 'pre') {
                md += '\\n\\n' + node.outerHTML + '\\n\\n';
                return;
            }
            if (tag === 'h1') md += '# ' + mdH2M(node, indent).trim() + '\\n\\n';
            else if (tag === 'h2') md += '## ' + mdH2M(node, indent).trim() + '\\n\\n';
            else if (tag === 'h3') md += '### ' + mdH2M(node, indent).trim() + '\\n\\n';
            else if (tag === 'h4') md += '#### ' + mdH2M(node, indent).trim() + '\\n\\n';
            else if (tag === 'h5') md += '##### ' + mdH2M(node, indent).trim() + '\\n\\n';
            else if (tag === 'h6') md += '###### ' + mdH2M(node, indent).trim() + '\\n\\n';
            else if (tag === 'p') md += mdH2M(node, indent).trim() + '\\n\\n';
            else if (tag === 'br') md += '\\n';
            // 用 HTML 标签而非 **/*：中文标点边界下 markdown 的 **粗体** 常无法闭合渲染，
            // inline HTML 在 markdown 中通用且渲染可靠
            else if (tag === 'strong' || tag === 'b') md += '<strong>' + mdH2M(node, indent) + '</strong>';
            else if (tag === 'em' || tag === 'i') md += '<em>' + mdH2M(node, indent) + '</em>';
            else if (tag === 'code' && node.parentElement && node.parentElement.tagName === 'PRE') md += mdH2M(node, indent);
            else if (tag === 'code') md += '`' + mdH2M(node, indent) + '`';
            else if (tag === 'pre') {
                var code = node.querySelector('code');
                var lang = '';
                if (code) { var cls = code.className.match(/language-(\\w+)/); if (cls) lang = cls[1]; }
                md += '```' + lang + '\\n' + (code || node).textContent + '\\n```\\n\\n';
            }
            else if (tag === 'a') md += '[' + mdH2M(node, indent) + '](' + (node.getAttribute('href') || '') + ')';
            else if (tag === 'img') md += '![' + (node.getAttribute('alt') || '') + '](' + (node.getAttribute('src') || '') + ')';
            else if (tag === 'ul') {
                var lis = node.querySelectorAll(':scope > li');
                lis.forEach(function(li) {
                    var liText = '';
                    var subList = '';
                    li.childNodes.forEach(function(c) {
                        if (c.nodeType === 1 && (c.tagName === 'UL' || c.tagName === 'OL')) {
                            subList += mdH2M(c, indent + '  ');
                        } else if (c.nodeType === 1) {
                            liText += mdH2M(c, indent);
                        } else if (c.nodeType === 3) {
                            liText += c.textContent;
                        }
                    });
                    md += indent + '- ' + liText.trim() + '\\n';
                    if (subList) md += subList;
                });
                if (!indent) md += '\\n';
            }
            else if (tag === 'ol') {
                var i = 1;
                var olis = node.querySelectorAll(':scope > li');
                olis.forEach(function(li) {
                    var liText = '';
                    var subList = '';
                    li.childNodes.forEach(function(c) {
                        if (c.nodeType === 1 && (c.tagName === 'UL' || c.tagName === 'OL')) {
                            subList += mdH2M(c, indent + '  ');
                        } else if (c.nodeType === 1) {
                            liText += mdH2M(c, indent);
                        } else if (c.nodeType === 3) {
                            liText += c.textContent;
                        }
                    });
                    md += indent + i + '. ' + liText.trim() + '\\n';
                    if (subList) md += subList;
                    i++;
                });
                if (!indent) md += '\\n';
            }
            else if (tag === 'blockquote') {
                var inner = mdH2M(node, indent).trim();
                inner.split('\\n').forEach(function(line) {
                    md += '> ' + line + '\\n';
                });
                md += '\\n';
            }
            else if (tag === 'hr') md += '---\\n\\n';
            else if (tag === 'table') {
                var rows = node.querySelectorAll('tr');
                rows.forEach(function(row, ri) {
                    var cells = row.querySelectorAll('th, td');
                    var line = '|';
                    cells.forEach(function(c) { line += ' ' + mdH2M(c, indent).trim() + ' |'; });
                    md += line + '\\n';
                    if (ri === 0) {
                        md += '|';
                        cells.forEach(function() { md += ' --- |'; });
                        md += '\\n';
                    }
                });
                md += '\\n';
            }
            else md += mdH2M(node, indent);
        });
        return md;
    }
    """

    /// 在 document 上运行转换器，返回 body 正文的 Markdown。
    static let convertBodyScript = converterSource + "\nmdH2M(document.body, '');"

    /// 转换结果清理：去行尾空格、折叠 3+ 连续空行为一个空行、去首尾空白。
    static func cleanConvertedMarkdown(_ markdown: String) -> String {
        markdown
            .replacingOccurrences(of: "[ \\t]+\\n", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
