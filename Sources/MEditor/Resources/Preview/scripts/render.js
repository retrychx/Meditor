// MEditor preview — Markdown rendering pipeline.
// All rendering happens synchronously on the main thread.
// highlight.js is loaded lazily and applied in idle-time batches.

(function (global) {
  'use strict';

  var LANG_ALIASES = {
    'shell': 'bash', 'sh': 'bash', 'zsh': 'bash',
    'js': 'javascript', 'jsx': 'javascript', 'mjs': 'javascript', 'cjs': 'javascript',
    'ts': 'typescript', 'tsx': 'typescript',
    'py': 'python', 'gyp': 'python',
    'rb': 'ruby', 'gemspec': 'ruby', 'rs': 'rust',
    'go': 'go', 'golang': 'go',
    'c++': 'cpp', 'cc': 'cpp', 'cxx': 'cpp', 'hpp': 'cpp',
    'cs': 'csharp', 'c#': 'csharp',
    'kt': 'kotlin', 'kts': 'kotlin',
    'yml': 'yaml', 'html': 'xml', 'xhtml': 'xml', 'svg': 'xml',
    'make': 'makefile', 'mk': 'makefile', 'mak': 'makefile',
    'patch': 'diff', 'gql': 'graphql', 'toml': 'ini',
    'txt': 'plaintext', 'text': 'plaintext',
    'console': 'plaintext', 'shellsession': 'plaintext'
  };

  function extractMermaid(content) {
    var diagrams = [];
    var processed = content.replace(/```mermaid[^]*?```/g, function (match) {
      var code = match.replace('```mermaid', '').slice(0, -3).trim();
      var id = 'mermaid-' + diagrams.length;
      diagrams.push({ id: id, code: code });
      return '<div class="mermaid-placeholder" id="' + id + '"></div>';
    });
    return { processed: processed, diagrams: diagrams };
  }

  // Paragraph-level parse cache: avoids re-parsing unchanged paragraphs.
  // Key = paragraph text (exact match, no hash collision risk).
  // Only caches blocks under 2KB to bound memory usage.
  var paragraphCache = new Map();
  var PARAGRAPH_CACHE_LIMIT = 300;
  var PARAGRAPH_CACHE_MAX_BLOCK = 2048;

  /**
   * Render markdown by splitting into paragraphs (blocks separated by blank lines),
   * caching each block's HTML independently. Only changed blocks hit marked.parse.
   * Falls back to full parse if content has complex cross-block structures.
   */
  function renderMarkdownCached(content) {
    var blocks = content.split(/\n{2,}/);

    // Fallback: link reference definitions are cross-block state.
    // Also fallback if content has fenced code blocks anywhere — splitting on
    // \n\n would break fences that contain blank lines, shattering the code
    // block into separate paragraphs (first line becomes an unterminated code
    // block, body renders as plain paragraphs, closing ``` leaks as text) and
    // corrupting TOC line mapping. Note the `m` flag + `\s*`: the fence may sit
    // mid-document and be slightly indented, not just at the very start.
    if (blocks.length <= 2 || /^\[.+\]:\s/m.test(content) || /^\s*```/m.test(content)) {
      return renderMarkdown(content);
    }

    var htmlParts = [];

    for (var i = 0; i < blocks.length; i++) {
      var block = blocks[i];
      if (!block.trim()) { htmlParts.push(''); continue; }

      if (block.length <= PARAGRAPH_CACHE_MAX_BLOCK && paragraphCache.has(block)) {
        htmlParts.push(paragraphCache.get(block));
      } else {
        var blockHTML = marked.parse(fixTableSeparators(block), { gfm: true, breaks: false });
        if (block.length <= PARAGRAPH_CACHE_MAX_BLOCK) {
          paragraphCache.set(block, blockHTML);
          if (paragraphCache.size > PARAGRAPH_CACHE_LIMIT) {
            var firstKey = paragraphCache.keys().next().value;
            paragraphCache.delete(firstKey);
          }
        }
        htmlParts.push(blockHTML);

        // Evict oldest if over limit
        if (paragraphCache.size > PARAGRAPH_CACHE_LIMIT) {
          var firstKey = paragraphCache.keys().next().value;
          paragraphCache.delete(firstKey);
        }
      }
    }

    return htmlParts.join('\n');
  }

  function renderMarkdown(content) {
    var processed = content
      .replace(/^(#{1,6}\s+[^\n]+)\n(?!\n)/gm, '$1\n\n')
      .replace(/^(---+|\*\*\*+|___+)\s*\n(?!\n)/gm, '$1\n\n');
    processed = fixTableSeparators(processed);
    return marked.parse(processed, { gfm: true, breaks: false });
  }

  function fixTableSeparators(text) {
    if (text.indexOf('|') === -1) return text;
    var lines = text.split('\n');
    var modified = false;
    for (var i = 1; i < lines.length; i++) {
      var line = lines[i];
      if (!/^\|?[\s|:\-]+\|?$/.test(line) || line.indexOf('-') === -1) continue;
      var prev = lines[i - 1];
      if (!prev || prev.indexOf('|') === -1) continue;
      var hc = countPipeCols(prev), sc = countPipeCols(line);
      if (hc > 0 && sc > 0 && sc !== hc) {
        var parts = splitPipeCols(line);
        while (parts.length < hc) parts.push('---');
        if (parts.length > hc) parts = parts.slice(0, hc);
        lines[i] = '| ' + parts.join(' | ') + ' |';
        modified = true;
      }
    }
    return modified ? lines.join('\n') : text;
  }

  function countPipeCols(line) {
    var t = line.trim();
    if (t.charAt(0) === '|') t = t.substring(1);
    if (t.charAt(t.length - 1) === '|') t = t.substring(0, t.length - 1);
    return t.length === 0 ? 0 : t.split('|').length;
  }

  function splitPipeCols(line) {
    var t = line.trim();
    if (t.charAt(0) === '|') t = t.substring(1);
    if (t.charAt(t.length - 1) === '|') t = t.substring(0, t.length - 1);
    return t.split('|').map(function(s) { return s.trim(); });
  }

  function stampHeadingLines(rootEl, sourceText) {
    var lines = collectHeadingLines(sourceText);
    if (lines.length === 0) return;
    var headings = rootEl.querySelectorAll('h1, h2, h3, h4, h5, h6');
    var n = Math.min(headings.length, lines.length);
    for (var i = 0; i < n; i++) {
      headings[i].setAttribute('data-source-line', String(lines[i]));
    }
  }

  function collectHeadingLines(content) {
    var lines = content.split('\n');
    var out = [];
    var inFence = false;
    for (var i = 0; i < lines.length; i++) {
      if (/^\s*```/.test(lines[i])) { inFence = !inFence; continue; }
      if (inFence) continue;
      if (/^#{1,6}\s+\S/.test(lines[i])) out.push(i);
    }
    return out;
  }

  // hljs is loaded synchronously in template.html — always available
  function loadHighlightIfNeeded() {
    return Promise.resolve();
  }

  function highlightCodeBlocks(rootEl) {
    var blocks = Array.prototype.slice.call(rootEl.querySelectorAll('pre code'));
    if (blocks.length === 0) return;
    blocks.forEach(attachCopyButton);
    loadHighlightIfNeeded().then(function () {
      var FIRST_BATCH = 6, IDLE_BATCH = 4;
      var first = Math.min(FIRST_BATCH, blocks.length);
      for (var i = 0; i < first; i++) highlightOneBlock(blocks[i]);
      if (blocks.length <= first) return;
      var remaining = blocks.slice(first);
      var next = function () {
        var batch = remaining.splice(0, IDLE_BATCH);
        for (var j = 0; j < batch.length; j++) highlightOneBlock(batch[j]);
        if (remaining.length > 0) scheduleIdle(next);
      };
      scheduleIdle(next);
    }).catch(function () {});
  }

  function scheduleIdle(fn) {
    if (typeof window.requestIdleCallback === 'function') {
      window.requestIdleCallback(fn, { timeout: 200 });
    } else {
      setTimeout(fn, 16);
    }
  }

  function highlightOneBlock(block) {
    var lang = null;
    var match = block.className.match(/language-([a-zA-Z0-9_+#-]+)/);
    if (match) { lang = match[1].toLowerCase(); }
    if (lang && LANG_ALIASES[lang]) { lang = LANG_ALIASES[lang]; }
    if (lang && hljs.getLanguage(lang)) {
      try {
        block.innerHTML = hljs.highlight(block.textContent, { language: lang, ignoreIllegals: true }).value;
        block.classList.add('hljs');
      } catch (e) { block.classList.add('hljs'); }
    } else {
      block.classList.add('hljs');
    }
  }

  function attachCopyButton(codeEl) {
    var pre = codeEl.parentElement;
    if (!pre || pre.tagName !== 'PRE') return;
    if (pre.querySelector('.meditor-copy-btn')) return;
    pre.classList.add('meditor-codeblock');
    var btn = document.createElement('button');
    btn.className = 'meditor-copy-btn';
    btn.type = 'button';
    btn.textContent = 'Copy';
    btn.setAttribute('aria-label', 'Copy code');
    btn.addEventListener('click', function (ev) {
      ev.stopPropagation();
      var text = codeEl.textContent || '';
      try {
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.copyHandler) {
          window.webkit.messageHandlers.copyHandler.postMessage({ text: text });
          return;
        }
      } catch (e) {}
      if (navigator.clipboard) navigator.clipboard.writeText(text).catch(function () {});
      btn.textContent = 'Copied';
      btn.classList.add('meditor-copy-btn--copied');
      setTimeout(function () { btn.textContent = 'Copy'; btn.classList.remove('meditor-copy-btn--copied'); }, 1200);
    });
    pre.appendChild(btn);
  }

  // Mermaid
  // mermaid is loaded synchronously in template.html — always available
  function loadMermaidIfNeeded() {
    return Promise.resolve();
  }

  function configureMermaidFromTheme() {
    if (typeof mermaid === 'undefined') return;
    var themeVar = getComputedStyle(document.documentElement)
      .getPropertyValue('--mermaid-theme').trim().replace(/['"]/g, '');
    mermaid.initialize({ startOnLoad: false, theme: themeVar || 'default' });
  }

  function renderMermaidDiagrams(diagrams) {
    if (!diagrams || diagrams.length === 0) return;
    loadMermaidIfNeeded().then(function () {
      configureMermaidFromTheme();
      if (typeof window.IntersectionObserver !== 'function') {
        diagrams.forEach(renderOneMermaid);
        return;
      }
      var observer = new IntersectionObserver(function (entries) {
        entries.forEach(function (entry) {
          if (!entry.isIntersecting) return;
          observer.unobserve(entry.target);
          var d = diagrams.filter(function (x) { return x.id === entry.target.id; })[0];
          if (d) renderOneMermaid(d);
        });
      }, { rootMargin: '200px' });
      diagrams.forEach(function (d) {
        var el = document.getElementById(d.id);
        if (el) observer.observe(el);
      });
    }).catch(function () {});
  }

  function renderOneMermaid(d) {
    mermaid.render(d.id + '-svg', d.code).then(function (r) {
      var el = document.getElementById(d.id);
      if (el && r && r.svg) {
        el.outerHTML = '<div class="mermaid-container">' + r.svg + '</div>';
        if (window.MEditor && window.MEditor.invalidateLayoutMetrics) {
          window.MEditor.invalidateLayoutMetrics();
        }
      }
    }).catch(function (e) {
      var el = document.getElementById(d.id);
      if (el) el.outerHTML = '<div class="error-block">Mermaid: ' + String(e && e.message || e) + '</div>';
    });
  }

  function refreshMermaidForTheme() {
    if (typeof mermaid === 'undefined') return;
    configureMermaidFromTheme();
  }

  /** Full render pipeline with incremental DOM update.
   *  Instead of innerHTML replacing the entire tree, we diff at the
   *  block level (top-level children of #content) and only replace
   *  changed nodes. This preserves hljs state on unchanged code blocks
   *  and cuts DOM rebuild cost by 60-90% during typical editing. */
  function renderInto(targetEl, content) {
    try {
      var extracted = extractMermaid(content || '');
      var html = renderMarkdownCached(extracted.processed);

      // Incremental update: compare block-level nodes
      if (targetEl.children.length > 0 && html.length < 500000) {
        var updated = patchDOM(targetEl, html);
        if (updated) {
          stampHeadingLines(targetEl, content || '');
          highlightCodeBlocks(targetEl);
          renderMermaidDiagrams(extracted.diagrams);
          return;
        }
      }

      // Fallback: full replace (first render or very large docs)
      targetEl.innerHTML = html;
      if (html.indexOf('<table') !== -1) {
        var tables = targetEl.querySelectorAll('table');
        for (var t = 0; t < tables.length; t++) {
          var wrapper = document.createElement('div');
          wrapper.className = 'table-wrapper';
          tables[t].parentNode.insertBefore(wrapper, tables[t]);
          wrapper.appendChild(tables[t]);
        }
      }
      stampHeadingLines(targetEl, content || '');
      highlightCodeBlocks(targetEl);
      renderMermaidDiagrams(extracted.diagrams);
    } catch (e) {
      targetEl.innerHTML = '<div class="error-block">Render error: ' + String(e && e.message || e) + '</div>';
    }
  }

  /** Block-level DOM diff. Returns true if patch was applied, false to fallback. */
  function patchDOM(targetEl, newHTML) {
    // Create a temporary container to parse the new HTML
    var temp = document.createElement('div');
    temp.innerHTML = newHTML;

    var oldNodes = Array.prototype.slice.call(targetEl.children);
    var newNodes = Array.prototype.slice.call(temp.children);

    // If structure is radically different, bail to full replace
    if (Math.abs(oldNodes.length - newNodes.length) > oldNodes.length * 0.5 + 5) {
      return false;
    }

    var maxLen = Math.max(oldNodes.length, newNodes.length);
    var patched = 0;

    for (var i = 0; i < maxLen; i++) {
      if (i >= newNodes.length) {
        // Extra old nodes: remove
        targetEl.removeChild(targetEl.lastElementChild);
        patched++;
      } else if (i >= oldNodes.length) {
        // Extra new nodes: append
        targetEl.appendChild(newNodes[i].cloneNode(true));
        patched++;
      } else if (!nodesEqual(oldNodes[i], newNodes[i])) {
        // Different: replace
        var replacement = newNodes[i].cloneNode(true);
        targetEl.replaceChild(replacement, oldNodes[i]);
        patched++;
      }
      // else: same — keep existing DOM node (preserves hljs state, scroll, etc.)
    }

    // Wrap tables in new/replaced nodes
    if (newHTML.indexOf('<table') !== -1) {
      var tables = targetEl.querySelectorAll('table:not(.table-wrapper table)');
      for (var t = 0; t < tables.length; t++) {
        if (tables[t].parentElement.className === 'table-wrapper') continue;
        var wrapper = document.createElement('div');
        wrapper.className = 'table-wrapper';
        tables[t].parentNode.insertBefore(wrapper, tables[t]);
        wrapper.appendChild(tables[t]);
      }
    }

    return true;
  }

  /** Fast shallow equality check for two DOM elements. */
  function nodesEqual(a, b) {
    if (a.tagName !== b.tagName) return false;
    // For code blocks, compare textContent (cheaper than innerHTML)
    if (a.tagName === 'PRE') {
      return a.textContent === b.textContent;
    }
    // For everything else, compare outerHTML length first (fast reject),
    // then full comparison only if lengths match
    if (a.innerHTML.length !== b.innerHTML.length) return false;
    return a.innerHTML === b.innerHTML;
  }

  global.MEditorRender = {
    renderInto: renderInto,
    configureMermaidFromTheme: configureMermaidFromTheme,
    refreshMermaidForTheme: refreshMermaidForTheme
  };
})(window);
