// MEditor preview — 启动引导。
// 初始内容放在 <script type="application/json"> 数据块里（CSP script-src 'self'
// 禁掉了内联脚本，不能再像原来那样内联 MEditor.boot(...)），这里读出后启动。

(function () {
  'use strict';
  document.addEventListener('DOMContentLoaded', function () {
    var content = '';
    try {
      var el = document.getElementById('meditor-initial-content');
      content = JSON.parse(el && el.textContent ? el.textContent : '""') || '';
    } catch (e) {
      content = '';
    }
    window.MEditor.boot(content);
  });
})();
