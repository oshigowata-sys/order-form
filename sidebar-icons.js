/*
 * 共通サイドバーアイコン（管理画面の全ページで読み込む）
 * 各 .nav-item / .logout-item の href（ファイル名）からアイコンを判定し、
 * 中の .icon に統一SVG線アイコンを注入する。絵文字を一掃し、全画面で見た目を揃える。
 * ★アイコンの定義はここ1箇所だけ（各HTMLに書かない＝ズレ防止）。
 */
(function () {
  if (window.__sidebarIconsInit) return;
  window.__sidebarIconsInit = true;

  var A = 'viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"';
  var ICONS = {
    'dashboard':      '<svg ' + A + '><path d="M3 9.5 12 3l9 6.5"/><path d="M5 9v11a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1V9"/><path d="M9 21v-7h6v7"/></svg>',
    'orders':         '<svg ' + A + '><path d="M16 4h2a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h2"/><rect x="8" y="2" width="8" height="4" rx="1"/><path d="M8 12h8M8 16h6"/></svg>',
    'invoice-list':   '<svg ' + A + '><path d="M5 21V4a1 1 0 0 1 1-1h12a1 1 0 0 1 1 1v17l-3-2-2 2-2-2-2 2-2-2-3 2z"/><path d="M9 8h6M9 12h6"/></svg>',
    'quotation-list': '<svg ' + A + '><path d="M14 3H6a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V9z"/><path d="M14 3v6h6"/><path d="M9 13h6M9 17h4"/></svg>',
    'customer':       '<svg ' + A + '><path d="M3 21h18"/><path d="M6 21V5a2 2 0 0 1 2-2h5a2 2 0 0 1 2 2v16"/><path d="M15 21V10h3a2 2 0 0 1 2 2v9"/><path d="M9 7h2M9 11h2M9 15h2"/></svg>',
    'products':       '<svg ' + A + '><path d="M21 16V8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16z"/><path d="m3.3 7 8.7 5 8.7-5"/><path d="M12 22V12"/></svg>',
    'pricing':        '<svg ' + A + '><path d="M20.6 13.4 13.4 20.6a2 2 0 0 1-2.8 0L2.6 12.6A2 2 0 0 1 2 11.2V4a2 2 0 0 1 2-2h7.2a2 2 0 0 1 1.4.6l8 8a2 2 0 0 1 0 2.8z"/><circle cx="7.5" cy="7.5" r="1.2"/></svg>',
    'settings':       '<svg ' + A + '><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/></svg>',
    'audit-log':      '<svg ' + A + '><path d="M3 12a9 9 0 1 0 3-6.7L3 8"/><path d="M3 3v5h5"/><path d="M12 8v4l3 2"/></svg>',
    'logout':         '<svg ' + A + '><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><path d="m16 17 5-5-5-5"/><path d="M21 12H9"/></svg>'
  };

  function keyFromHref(href) {
    if (!href) return null;
    var file = href.split('/').pop().split('?')[0].split('#')[0];
    if (file === '' || file === 'dashboard.html') return 'dashboard';
    return file.replace(/\.html$/, '');
  }

  function injectStyle() {
    if (document.getElementById('sidebar-icons-style')) return;
    var css =
      '.nav-item .icon,.logout-item .icon{display:inline-flex;align-items:center;justify-content:center;width:20px;height:20px}' +
      '.nav-item .icon svg,.logout-item .icon svg{width:18px;height:18px;stroke-width:1.75}';
    var s = document.createElement('style');
    s.id = 'sidebar-icons-style';
    s.textContent = css;
    (document.head || document.documentElement).appendChild(s);
  }

  function apply() {
    injectStyle();
    var navs = document.querySelectorAll('.sidebar .nav-item');
    for (var i = 0; i < navs.length; i++) {
      var key = keyFromHref(navs[i].getAttribute('href'));
      var icon = navs[i].querySelector('.icon');
      if (icon && key && ICONS[key]) icon.innerHTML = ICONS[key];
    }
    var logout = document.querySelector('.sidebar .logout-item .icon');
    if (logout) logout.innerHTML = ICONS['logout'];
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', apply);
  } else {
    apply();
  }
})();
