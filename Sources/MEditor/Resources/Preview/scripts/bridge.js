// MEditor preview — JS↔Swift bridge.
// Exposes window.MEditor with the public API consumed by Swift's evaluateJavaScript.

(function (global) {
  'use strict';

  var contentEl = null;
  var ignoreScrollEvent = false;
  var lastReportedScrollPercent = -1;
  /// We track only the hash of the last content, never the full string.
  /// String equality on large markdown documents (hundreds of KB) would be
  /// O(n) on every SwiftUI updateNSView call.
  var lastContentHash = '';

  // LRU cache: content hash → fully-rendered innerHTML.
  // Skips marked + hljs + mermaid pipeline entirely when revisiting a file.
  var RENDER_CACHE_LIMIT = 8;
  var renderCache = new Map();
  var pendingCacheKey = null;

  /** Cheap 32-bit string hash (FNV-1a). Safe for cache keys, not crypto. */
  function fastHash(s) {
    var h = 0x811c9dc5;
    for (var i = 0; i < s.length; i++) {
      h ^= s.charCodeAt(i);
      h = (h + ((h << 1) + (h << 4) + (h << 7) + (h << 8) + (h << 24))) >>> 0;
    }
    return h.toString(36);
  }

  /** LRU touch: re-insert to mark as most-recently used. */
  function lruTouch(key, value) {
    if (renderCache.has(key)) renderCache.delete(key);
    renderCache.set(key, value);
    while (renderCache.size > RENDER_CACHE_LIMIT) {
      var firstKey = renderCache.keys().next().value;
      renderCache.delete(firstKey);
    }
  }

  /** Initial mount called by Swift after the page loads. */
  function boot(initialContent) {
    contentEl = document.getElementById('content');
    if (!contentEl) {
      console.error('MEditor: #content element not found');
      return;
    }
    var initial = initialContent || '';
    lastContentHash = fastHash(initial);
    if (window.MEditorRender) {
      window.MEditorRender.configureMermaidFromTheme();
      window.MEditorRender.renderInto(contentEl, initial);
    }
    attachScrollListener();
    sendTOC();
  }

  /** Re-render with new markdown content (no full page reload). */
  function update(newContent) {
    if (!contentEl) return;
    var content = newContent || '';
    var key = fastHash(content);
    if (key === lastContentHash) return;
    lastContentHash = key;

    // Cache hit: paint instantly. No marked / hljs / mermaid work needed.
    if (renderCache.has(key)) {
      contentEl.innerHTML = renderCache.get(key);
      lruTouch(key, renderCache.get(key));
      pendingCacheKey = null;
      sendTOC();
      return;
    }

    // Cache miss: full pipeline. Snapshot the result after idle work completes
    // so the cache reflects the fully-highlighted final HTML, not a half-rendered one.
    pendingCacheKey = key;
    if (window.MEditorRender) {
      window.MEditorRender.renderInto(contentEl, content);
    }
    scheduleCacheSnapshot(key, content);
    sendTOC();
  }

  function scheduleCacheSnapshot(key, content) {
    var snap = function () {
      // Only snapshot if this is still the current content
      // (user may have switched away while highlighting was running).
      if (pendingCacheKey !== key) return;
      lruTouch(key, contentEl.innerHTML);
    };
    if (typeof window.requestIdleCallback === 'function') {
      window.requestIdleCallback(snap, { timeout: 1500 });
    } else {
      setTimeout(snap, 500);
    }
  }

  /** Switch theme by toggling a class on <html>.
   *  All theme stylesheets are inlined in css/themes.css, so this is a
   *  pure class change with zero network or stylesheet-swap cost. */
  function setTheme(themeName) {
    var safe = String(themeName || '').toLowerCase().replace(/[^a-z0-9_-]/g, '');
    if (!safe) return;
    var root = document.documentElement;
    // Strip any previous theme-* class, set the new one.
    root.className = root.className.replace(/\btheme-[a-z0-9_-]+\b/g, '').trim();
    root.classList.add('theme-' + safe);
    // Cached HTML doesn't depend on theme anymore (hljs colors come from CSS),
    // so we don't clear renderCache. Mermaid SVGs do bake in colors though,
    // so re-render only diagrams to refresh their theming.
    if (window.MEditorRender) {
      window.MEditorRender.refreshMermaidForTheme();
    }
  }

  /** Programmatic scroll from Swift side (e.g. editor scroll → preview sync). */
  function scrollToPercent(percent) {
    var docHeight = document.documentElement.scrollHeight - window.innerHeight;
    var y = docHeight > 0 ? docHeight * percent : 0;
    ignoreScrollEvent = true;
    window.scrollTo(0, y);
    // Allow the scroll event to fire and be skipped, then resume reporting.
    setTimeout(function () { ignoreScrollEvent = false; }, 50);
  }

  /** Scroll to the rendered element whose source line is closest to (but not
   *  greater than) the given line. Used by Swift for editor→preview sync. */
  function scrollToLine(line) {
    if (!contentEl) return;
    var anchors = contentEl.querySelectorAll('[data-source-line]');
    if (anchors.length === 0) return;
    // Find the last anchor whose data-source-line <= target line.
    var target = null;
    for (var i = 0; i < anchors.length; i++) {
      var l = parseInt(anchors[i].getAttribute('data-source-line'), 10);
      if (isNaN(l)) continue;
      if (l <= line) target = anchors[i];
      else break;
    }
    if (!target) target = anchors[0];
    ignoreScrollEvent = true;
    var rect = target.getBoundingClientRect();
    window.scrollTo({ top: window.scrollY + rect.top - 16, behavior: 'auto' });
    setTimeout(function () { ignoreScrollEvent = false; }, 50);
  }

  /** Return rendered HTML for export. Includes inlined CSS for portability. */
  function getRenderedHTML(documentTitle) {
    if (!contentEl) return '';
    var title = String(documentTitle || 'Document');
    // Inline all stylesheets so the exported HTML is self-contained.
    var styles = '';
    var sheets = document.querySelectorAll('link[rel="stylesheet"]');
    for (var i = 0; i < sheets.length; i++) {
      try {
        var rules = sheets[i].sheet && sheets[i].sheet.cssRules;
        if (rules) {
          for (var j = 0; j < rules.length; j++) {
            styles += rules[j].cssText + '\n';
          }
        }
      } catch (e) { /* CORS or other issue, skip */ }
    }
    var styleTags = document.querySelectorAll('style');
    for (var k = 0; k < styleTags.length; k++) {
      styles += styleTags[k].innerHTML + '\n';
    }
    return [
      '<!DOCTYPE html>',
      '<html lang="en"><head><meta charset="UTF-8">',
      '<title>' + escapeHtml(title) + '</title>',
      '<style>' + styles + '</style>',
      '</head><body><div id="content">',
      contentEl.innerHTML,
      '</div></body></html>'
    ].join('\n');
  }

  function escapeHtml(s) {
    return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }

  function attachScrollListener() {
    window.addEventListener('scroll', function () {
      if (ignoreScrollEvent) return;
      var docHeight = document.documentElement.scrollHeight - window.innerHeight;
      var percent = docHeight > 0 ? window.scrollY / docHeight : 0;
      if (Math.abs(percent - lastReportedScrollPercent) < 0.005) return;
      lastReportedScrollPercent = percent;

      // Find the topmost visible source-line anchor for preview→editor sync.
      var line = currentVisibleLine();

      try {
        window.webkit.messageHandlers.scrollHandler.postMessage({
          percent: percent,
          line: line
        });
      } catch (e) { /* Swift handler not registered */ }
    });
  }

  /// Return the data-source-line of the topmost anchor currently visible in
  /// the viewport, or -1 if none exists / nothing in view.
  function currentVisibleLine() {
    if (!contentEl) return -1;
    var anchors = contentEl.querySelectorAll('[data-source-line]');
    var topmost = null;
    var topmostY = Infinity;
    for (var i = 0; i < anchors.length; i++) {
      var rect = anchors[i].getBoundingClientRect();
      // Anchors above viewport (rect.bottom < 0) are skipped; we want the
      // first one within or just past the top edge.
      if (rect.bottom < 0) continue;
      if (rect.top < topmostY) {
        topmostY = rect.top;
        topmost = anchors[i];
      }
    }
    if (!topmost) return -1;
    var l = parseInt(topmost.getAttribute('data-source-line'), 10);
    return isNaN(l) ? -1 : l;
  }

  /** Set the document base URL so relative image/link/asset paths in
   *  markdown resolve against the source file's parent directory. */
  function setBaseURL(url) {
    var safe = String(url || '');
    var existing = document.querySelector('base');
    if (existing) {
      existing.href = safe;
    } else if (safe) {
      var base = document.createElement('base');
      base.href = safe;
      document.head.insertBefore(base, document.head.firstChild);
    }
  }

  /** Extract headings from rendered content and send to Swift as TOC. */
  function sendTOC() {
    if (!contentEl) return;
    var headings = contentEl.querySelectorAll('h1, h2, h3, h4, h5, h6');
    var items = [];
    for (var i = 0; i < headings.length; i++) {
      var el = headings[i];
      var level = parseInt(el.tagName.charAt(1), 10);
      var line = parseInt(el.getAttribute('data-source-line') || '-1', 10);
      items.push({ level: level, title: el.textContent || '', line: line });
    }
    try {
      window.webkit.messageHandlers.tocHandler.postMessage({ items: items });
    } catch (e) { /* handler not registered */ }
  }

  global.MEditor = {
    boot: boot,
    update: update,
    setTheme: setTheme,
    setBaseURL: setBaseURL,
    scrollToPercent: scrollToPercent,
    scrollToLine: scrollToLine,
    getRenderedHTML: getRenderedHTML
  };
})(window);
