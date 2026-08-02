/* MEditor 演讲模式：逐页 marked.parse 渲染，绝对定位叠放，显隐切换。 */
window.MEditorSlides = (function () {
  var slides = [];
  var current = 0;
  var stage = null;
  var indicator = null;

  // payload: { slides: [String], theme: 'github'|'nord'|'dracula', baseHref: String }
  function boot(payload) {
    slides = payload.slides || [];
    document.documentElement.className = 'theme-' + (payload.theme || 'github');

    // 相对图片路径通过 <base> 解析到源文件目录（meditor-asset:// scheme）
    if (payload.baseHref) {
      var base = document.createElement('base');
      base.href = payload.baseHref;
      document.head.appendChild(base);
    }

    stage = document.getElementById('stage');
    indicator = document.getElementById('indicator');
    renderAll();
    show(0);

    document.addEventListener('keydown', onKey);
    document.addEventListener('click', onClick);
  }

  function renderAll() {
    for (var i = 0; i < slides.length; i++) {
      var el = document.createElement('div');
      el.className = 'slide';
      var inner = document.createElement('div');
      inner.className = 'slide-content';
      inner.innerHTML = marked.parse(slides[i], { gfm: true, breaks: false });
      // 首个元素是 h1 的页按封面页排版（大标题 + 强调短条 + 弱化副信息）
      if (inner.firstElementChild && inner.firstElementChild.tagName === 'H1') {
        el.classList.add('cover');
      }
      el.appendChild(inner);
      stage.appendChild(el);
    }
    stage.querySelectorAll('pre code').forEach(function (block) {
      // 与预览一致：仅对已知语言做高亮，避免自动检测误伤普通文本块
      var match = block.className.match(/language-([a-zA-Z0-9_+#-]+)/);
      var lang = match ? match[1].toLowerCase() : null;
      if (lang && hljs.getLanguage(lang)) {
        try {
          block.innerHTML = hljs.highlight(block.textContent, { language: lang, ignoreIllegals: true }).value;
        } catch (e) { /* 忽略高亮失败，保留原文 */ }
      }
      block.classList.add('hljs');
    });
  }

  function show(index) {
    if (!slides.length) return;
    current = Math.max(0, Math.min(index, slides.length - 1));
    var nodes = stage.children;
    for (var i = 0; i < nodes.length; i++) {
      nodes[i].classList.toggle('active', i === current);
    }
    indicator.textContent = (current + 1) + ' / ' + slides.length;
    var progress = document.getElementById('progress');
    if (progress) {
      progress.style.width = ((current + 1) / slides.length * 100) + 'vw';
    }
  }

  function next() { show(current + 1); }
  function prev() { show(current - 1); }

  function exit() {
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.presentationExit) {
      window.webkit.messageHandlers.presentationExit.postMessage({});
    }
  }

  function onKey(e) {
    switch (e.key) {
      case 'ArrowRight':
      case 'ArrowDown':
      case ' ':
      case 'PageDown':
        e.preventDefault(); next(); break;
      case 'ArrowLeft':
      case 'ArrowUp':
      case 'PageUp':
        e.preventDefault(); prev(); break;
      case 'Home':
        e.preventDefault(); show(0); break;
      case 'End':
        e.preventDefault(); show(slides.length - 1); break;
      case 'Escape':
        e.preventDefault(); exit(); break;
    }
  }

  // 右半屏下一页，左半屏上一页；链接不响应（防止放映页被导航走）
  function onClick(e) {
    if (e.target.closest && e.target.closest('a')) { e.preventDefault(); return; }
    if (e.clientX >= window.innerWidth / 2) { next(); } else { prev(); }
  }

  return { boot: boot, show: show, next: next, prev: prev };
})();
