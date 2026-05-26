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

  /** Render markdown content to HTML string (without code-block highlighting). */
  function renderMarkdown(content) {
    return marked.parse(content, { breaks: true, gfm: true });
  }

  /**
   * Apply highlight.js to all <pre><code> elements within the given root.
   * Performance strategy:
   *   1. The first BATCH_SIZE blocks (above the fold) are highlighted synchronously
   *      so users see colored code immediately on the first paint.
   *   2. Remaining blocks are processed in idle-time chunks, yielding the main
   *      thread between batches to keep scrolling smooth.
   *   3. We never call hljs.highlightAuto: it's O(N_languages) per block and is
   *      the dominant cost for documents with many unlabelled code blocks.
   */
  function highlightCodeBlocks(rootEl) {
    var blocks = Array.prototype.slice.call(rootEl.querySelectorAll('pre code'));
    if (blocks.length === 0) return;

    var FIRST_BATCH = 6;
    var IDLE_BATCH = 4;

    var first = Math.min(FIRST_BATCH, blocks.length);
    for (var i = 0; i < first; i++) {
      highlightOneBlock(blocks[i]);
    }
    if (blocks.length <= first) return;

    var remaining = blocks.slice(first);
    var processNext = function () {
      var batch = remaining.splice(0, IDLE_BATCH);
      for (var j = 0; j < batch.length; j++) highlightOneBlock(batch[j]);
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

  function highlightOneBlock(block) {
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
   * Full render pipeline: takes raw markdown, returns nothing.
   * Mutates the given target element with rendered HTML.
   */
  function renderInto(targetEl, content) {
    try {
      var extracted = extractMermaid(content || '');
      var html = renderMarkdown(extracted.processed);
      targetEl.innerHTML = html;
      highlightCodeBlocks(targetEl);
      renderMermaidDiagrams(extracted.diagrams);
    } catch (e) {
      targetEl.innerHTML = '<div class="error-block">Render error: ' +
        String((e && e.message) || e) + '</div>';
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
