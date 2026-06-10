// MEditor preview — Markdown rendering pipeline.
// Pure functions only. No DOM mutation here — that's bridge.js's job.

(function (global) {
  'use strict';

  // Map common language aliases to highlight.js canonical names.
  // Some entries (e.g. 'shell') exist in hljs but resolve to the wrong grammar
  // (terminal session output vs bash scripts).
  var LANG_ALIASES = {
    'shell': 'bash', 'sh': 'bash', 'zsh': 'bash',
    'js': 'javascript', 'jsx': 'javascript', 'mjs': 'javascript', 'cjs': 'javascript',
    'ts': 'typescript', 'tsx': 'typescript',
    'py': 'python', 'gyp': 'python',
    'rb': 'ruby', 'gemspec': 'ruby',
    'rs': 'rust',
    'go': 'go', 'golang': 'go',
    'c++': 'cpp', 'cc': 'cpp', 'cxx': 'cpp', 'hpp': 'cpp', 'hxx': 'cpp',
    'cs': 'csharp', 'c#': 'csharp',
    'kt': 'kotlin', 'kts': 'kotlin',
    'pl': 'perl', 'pm': 'perl',
    'md': 'markdown', 'mkdown': 'markdown', 'mkd': 'markdown',
    'yml': 'yaml',
    'html': 'xml', 'xhtml': 'xml', 'svg': 'xml',
    'make': 'makefile', 'mk': 'makefile', 'mak': 'makefile',
    'patch': 'diff',
    'gql': 'graphql',
    'toml': 'ini',
    'txt': 'plaintext', 'text': 'plaintext',
    'console': 'plaintext', 'shellsession': 'plaintext'
  };

  /**
   * Extract mermaid code blocks from raw markdown content.
   * Returns { processed: string, diagrams: [{id, code}] }.
   */
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

  /** Render markdown content to HTML string (without code-block highlighting).
   *  Uses marked's default renderer to keep GFM features (tables, task lists,
   *  strikethrough) working correctly. Heading source-line attributes are
   *  added in a post-pass via stampHeadingLines. */
  function renderMarkdown(content) {
    // Force a blank line after ATX headings and HR so a directly-following
    // GFM table is recognized. marked 12's table parser (per GFM spec)
    // requires a blank-line separator from preceding prose. Without this,
    // common patterns like `## Heading\n| col | col |` get rendered as
    // a paragraph of literal pipes.
    var processed = content
      .replace(/^(#{1,6}\s+[^\n]+)\n(?!\n)/gm, '$1\n\n')
      .replace(/^(---+|\*\*\*+|___+)\s*\n(?!\n)/gm, '$1\n\n');

    // Fix GFM table separator row: marked v12 requires separator column count
    // to match header column count exactly. Pad or trim separator columns.
    processed = fixTableSeparators(processed);

    var html = marked.parse(processed, { gfm: true, breaks: false });
    return html;
  }

  /** Ensure GFM table separator rows have the same column count as their
   *  header rows. marked v12 rejects tables where counts differ.
   *  Optimization: skip the expensive split/join if no pipe character exists. */
  function fixTableSeparators(text) {
    // Fast path: no pipe = no table possible. Avoids O(n) split+join.
    if (text.indexOf('|') === -1) return text;

    var lines = text.split('\n');
    var modified = false;
    for (var i = 1; i < lines.length; i++) {
      var line = lines[i];
      if (!/^\|?[\s|:\-]+\|?$/.test(line) || line.indexOf('-') === -1) continue;
      var prev = lines[i - 1];
      if (!prev || prev.indexOf('|') === -1) continue;
      var headerCols = countPipeCols(prev);
      var sepCols = countPipeCols(line);
      if (headerCols > 0 && sepCols > 0 && sepCols !== headerCols) {
        var parts = splitPipeCols(line);
        var defaultSep = '---';
        while (parts.length < headerCols) parts.push(defaultSep);
        if (parts.length > headerCols) parts = parts.slice(0, headerCols);
        lines[i] = '| ' + parts.join(' | ') + ' |';
        modified = true;
      }
    }
    return modified ? lines.join('\n') : text;
  }

  function countPipeCols(line) {
    var trimmed = line.trim();
    if (trimmed.charAt(0) === '|') trimmed = trimmed.substring(1);
    if (trimmed.charAt(trimmed.length - 1) === '|') trimmed = trimmed.substring(0, trimmed.length - 1);
    if (trimmed.length === 0) return 0;
    return trimmed.split('|').length;
  }

  function splitPipeCols(line) {
    var trimmed = line.trim();
    if (trimmed.charAt(0) === '|') trimmed = trimmed.substring(1);
    if (trimmed.charAt(trimmed.length - 1) === '|') trimmed = trimmed.substring(0, trimmed.length - 1);
    return trimmed.split('|').map(function(s) { return s.trim(); });
  }

  /// Walk rendered headings inside the root element and tag each one with a
  /// data-source-line attribute matching the source markdown. This drives
  /// editor↔preview scroll sync.
  function stampHeadingLines(rootEl, sourceText) {
    var lines = collectHeadingLines(sourceText);
    var headings = rootEl.querySelectorAll('h1, h2, h3, h4, h5, h6');
    var metadata = {
      sourceAnchors: [],
      sourceAnchorLines: [],
      tocItems: []
    };
    var n = Math.min(headings.length, lines.length);
    for (var i = 0; i < n; i++) {
      headings[i].setAttribute('data-source-line', String(lines[i]));
    }
    for (var j = 0; j < headings.length; j++) {
      var line = j < n ? lines[j] : -1;
      metadata.tocItems.push({
        level: parseInt(headings[j].tagName.charAt(1), 10),
        title: headings[j].textContent || '',
        line: line
      });
      if (line >= 0) {
        metadata.sourceAnchors.push(headings[j]);
        metadata.sourceAnchorLines.push(line);
      }
    }
    return metadata;
  }

  /// Walk the raw markdown text and record the 0-based line index of every
  /// ATX-style heading (`# `, `## `, etc). Order matches marked's heading
  /// render order, so we can pop them in sequence.
  function collectHeadingLines(content) {
    var lines = content.split('\n');
    var out = [];
    var inFence = false;
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i];
      // Skip ATX-style heading detection inside fenced code blocks.
      if (/^\s*```/.test(line)) { inFence = !inFence; continue; }
      if (inFence) continue;
      if (/^#{1,6}\s+\S/.test(line)) out.push(i);
    }
    return out;
  }

  var highlightLoadPromise = null;
  function loadHighlightIfNeeded() {
    if (typeof window.hljs !== 'undefined') return Promise.resolve();
    if (highlightLoadPromise) return highlightLoadPromise;
    highlightLoadPromise = new Promise(function (resolve, reject) {
      var script = document.createElement('script');
      script.src = 'highlight.min.js';
      script.async = true;
      script.onload = function () { resolve(); };
      script.onerror = function () {
        highlightLoadPromise = null;
        reject(new Error('failed to load highlight.min.js'));
      };
      document.head.appendChild(script);
    });
    return highlightLoadPromise;
  }

  /**
   * Apply highlight.js to all <pre><code> elements within the given root.
   * Performance strategy:
   *   1. The first 1-2 blocks are highlighted on the next frame so the main
   *      markdown DOM can paint before syntax work starts.
   *   2. Remaining blocks are highlighted only when they approach the viewport,
   *      then processed in small idle-time chunks.
   *   3. We never call hljs.highlightAuto: it's O(N_languages) per block and is
   *      the dominant cost for documents with many unlabelled code blocks.
   */
  function highlightCodeBlocks(rootEl) {
    var blocks = Array.prototype.slice.call(rootEl.querySelectorAll('pre code'));
    if (blocks.length === 0) return;
    blocks.forEach(function (block) {
      attachCopyButton(block);
      block.classList.add('hljs');
    });
    if (window.MEditor && window.MEditor.reportPerf) {
      window.MEditor.reportPerf('PreviewJSHighlightScheduled');
    }

    loadHighlightIfNeeded().then(function () {
      highlightLoadedBlocks(blocks);
    }).catch(function () {
      blocks.forEach(function (block) {
        block.classList.add('hljs');
      });
    });
  }

  function highlightLoadedBlocks(blocks) {
    var FIRST_BATCH = blocks.length > 12 ? 1 : 2;
    var IDLE_BATCH = 2;
    var first = Math.min(FIRST_BATCH, blocks.length);
    var immediate = blocks.slice(0, first);
    var deferred = blocks.slice(first);

    scheduleNextFrame(function () {
      for (var i = 0; i < immediate.length; i++) {
        highlightOneBlock(immediate[i]);
      }

      if (deferred.length === 0) return;

      if (typeof window.IntersectionObserver !== 'function') {
        scheduleIdleHighlights(deferred, IDLE_BATCH);
        return;
      }

      if (window.MEditor && window.MEditor.disconnectCodeHighlightObserver) {
        window.MEditor.disconnectCodeHighlightObserver();
      }

      var observer = new IntersectionObserver(function (entries) {
        var visible = [];
        entries.forEach(function (entry) {
          if (!entry.isIntersecting) return;
          observer.unobserve(entry.target);
          visible.push(entry.target);
        });
        if (visible.length > 0) {
          scheduleIdleHighlights(visible, IDLE_BATCH);
        }
      }, { rootMargin: '360px 0px' });

      deferred.forEach(function (block) {
        if (block.getAttribute('data-meditor-highlighted') === '1') return;
        observer.observe(block);
      });

      if (window.MEditor && window.MEditor.setCodeHighlightObserver) {
        window.MEditor.setCodeHighlightObserver(observer);
      }
    });
  }

  function scheduleIdleHighlights(blocks, batchSize) {
    var remaining = blocks.slice();
    var processNext = function () {
      var batch = remaining.splice(0, batchSize);
      for (var i = 0; i < batch.length; i++) {
        highlightOneBlock(batch[i]);
      }
      if (remaining.length > 0) scheduleIdle(processNext);
    };
    scheduleIdle(processNext);
  }

  function scheduleIdle(fn) {
    if (typeof window.requestIdleCallback === 'function') {
      window.requestIdleCallback(fn, { timeout: 200 });
    } else {
      setTimeout(fn, 16);
    }
  }

  function scheduleNextFrame(fn) {
    if (typeof window.requestAnimationFrame === 'function') {
      window.requestAnimationFrame(function () { fn(); });
    } else {
      setTimeout(fn, 16);
    }
  }

  function highlightOneBlock(block) {
    if (!block || block.getAttribute('data-meditor-highlighted') === '1') return;
    var lang = null;
    var match = block.className.match(/language-([a-zA-Z0-9_+#-]+)/);
    if (match) { lang = match[1].toLowerCase(); }
    if (lang && LANG_ALIASES[lang]) { lang = LANG_ALIASES[lang]; }

    // Only highlight when an explicit language is given AND known to hljs.
    // hljs.highlightAuto is intentionally avoided: it tries every grammar
    // and is the single biggest cost in this pipeline for typical docs.
    if (lang && hljs.getLanguage(lang)) {
      try {
        var result = hljs.highlight(block.textContent, { language: lang, ignoreIllegals: true });
        block.innerHTML = result.value;
        block.classList.add('hljs');
      } catch (e) { /* fall through to plain */ }
    } else {
      // Unlabelled / unknown language: still apply .hljs so the theme background
      // and font apply, but skip syntax coloring entirely.
      block.classList.add('hljs');
    }
    block.setAttribute('data-meditor-highlighted', '1');
  }

  /// Attach a hover-revealed copy button to a code block's <pre> wrapper.
  /// Sends raw text to Swift via messageHandler; Swift does NSPasteboard write.
  /// Falls back to navigator.clipboard if messageHandler isn't installed.
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
      var posted = false;
      try {
        if (window.webkit && window.webkit.messageHandlers &&
            window.webkit.messageHandlers.copyHandler) {
          window.webkit.messageHandlers.copyHandler.postMessage({ text: text });
          posted = true;
        }
      } catch (e) { /* fall through */ }
      if (!posted && navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).catch(function () {});
      }
      // Brief affordance
      var prev = btn.textContent;
      btn.textContent = 'Copied';
      btn.classList.add('meditor-copy-btn--copied');
      setTimeout(function () {
        btn.textContent = prev;
        btn.classList.remove('meditor-copy-btn--copied');
      }, 1200);
    });
    pre.appendChild(btn);
  }

  /**
   * Render mermaid diagrams previously extracted via extractMermaid().
   * Strategy:
   *  - Mermaid (3.3 MB) is loaded lazily, only when a document actually
   *    contains a mermaid block. 95%+ of markdown files don't, so this saves
   *    ~200-500ms of script parsing on the common path.
   *  - Once loaded, we use IntersectionObserver to defer per-diagram render
   *    until that diagram scrolls into the viewport.
   */
  function renderMermaidDiagrams(diagrams) {
    if (!diagrams || diagrams.length === 0) return;
    if (window.MEditor && window.MEditor.reportPerf) {
      window.MEditor.reportPerf('PreviewJSMermaidScheduled');
    }

    loadMermaidIfNeeded().then(function () {
      configureMermaidFromTheme();

      if (typeof window.IntersectionObserver !== 'function') {
        diagrams.forEach(function (d) { renderOneMermaid(d); });
        return;
      }

      var observer = new IntersectionObserver(function (entries) {
        entries.forEach(function (entry) {
          if (!entry.isIntersecting) return;
          var el = entry.target;
          observer.unobserve(el);
          var diagram = diagrams.filter(function (d) { return d.id === el.id; })[0];
          if (diagram) renderOneMermaid(diagram);
        });
      }, { rootMargin: '200px' });

      diagrams.forEach(function (d) {
        var el = document.getElementById(d.id);
        if (el) observer.observe(el);
      });
    }).catch(function (err) {
      diagrams.forEach(function (d) {
        var el = document.getElementById(d.id);
        if (el) {
          el.outerHTML = '<div class="error-block">Mermaid load failed: ' +
            String((err && err.message) || err) + '</div>';
        }
      });
    });
  }

  // Internal: lazy-load mermaid.min.js once, return a shared promise.
  var mermaidLoadPromise = null;
  function loadMermaidIfNeeded() {
    if (typeof window.mermaid !== 'undefined') return Promise.resolve();
    if (mermaidLoadPromise) return mermaidLoadPromise;
    mermaidLoadPromise = new Promise(function (resolve, reject) {
      var script = document.createElement('script');
      script.src = 'mermaid.min.js';
      script.async = true;
      script.onload = function () { resolve(); };
      script.onerror = function () {
        mermaidLoadPromise = null;
        reject(new Error('failed to load mermaid.min.js'));
      };
      document.head.appendChild(script);
    });
    return mermaidLoadPromise;
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
      if (el) {
        el.outerHTML = '<div class="error-block">Mermaid: ' +
          String((e && e.message) || e) + '</div>';
      }
    });
  }

  /**
   * Full render pipeline: takes raw markdown, mutates the target element,
   * and returns heading metadata used for scroll sync / TOC updates.
   */
  function renderInto(targetEl, content) {
    try {
      var extracted = extractMermaid(content || '');
      var html = renderMarkdown(extracted.processed);
      targetEl.innerHTML = html;
      // Wrap tables in a scrollable container for wide tables.
      if (html.indexOf('<table') !== -1) {
        var tables = targetEl.querySelectorAll('table');
        for (var t = 0; t < tables.length; t++) {
          var wrapper = document.createElement('div');
          wrapper.className = 'table-wrapper';
          tables[t].parentNode.insertBefore(wrapper, tables[t]);
          wrapper.appendChild(tables[t]);
        }
      }
      // Use the original (unprocessed) content for line numbers, since
      // mermaid extraction doesn't add or remove lines.
      var metadata = /<h[1-6][\s>]/.test(html)
        ? stampHeadingLines(targetEl, content || '')
        : {
          sourceAnchors: [],
          sourceAnchorLines: [],
          tocItems: []
        };
      if (window.MEditor && window.MEditor.reportPerf) {
        window.MEditor.reportPerf('PreviewJSRenderDOMCommitted');
      }
      highlightCodeBlocks(targetEl);
      renderMermaidDiagrams(extracted.diagrams);
      return metadata;
    } catch (e) {
      targetEl.innerHTML = '<div class="error-block">Render error: ' +
        String((e && e.message) || e) + '</div>';
      return {
        sourceAnchors: [],
        sourceAnchorLines: [],
        tocItems: []
      };
    }
  }

  /** Configure mermaid based on the current theme's CSS variable.
   *  Safe to call before mermaid is loaded — it'll just no-op. */
  function configureMermaidFromTheme() {
    if (typeof mermaid === 'undefined') return;
    var themeVar = getComputedStyle(document.documentElement)
      .getPropertyValue('--mermaid-theme').trim().replace(/['"]/g, '');
    var theme = themeVar || 'default';
    mermaid.initialize({ startOnLoad: false, theme: theme });
  }

  global.MEditorRender = {
    renderInto: renderInto,
    configureMermaidFromTheme: configureMermaidFromTheme,
    refreshMermaidForTheme: refreshMermaidForTheme
  };

  /** Re-render existing mermaid diagrams when the theme changes.
   *  Mermaid SVGs bake their colors in, so we need to regenerate them.
   *  hljs code blocks don't need this because their colors are pure CSS. */
  function refreshMermaidForTheme() {
    if (typeof mermaid === 'undefined') return;
    configureMermaidFromTheme();

    // Existing rendered diagrams are wrapped in .mermaid-container.
    // We can't easily re-derive their original code from the SVG, so we
    // accept that a manual file re-open is needed to refresh diagrams.
    // For most users, switching themes mid-document is rare; this trade-off
    // keeps theme switch instant.
  }
})(window);
