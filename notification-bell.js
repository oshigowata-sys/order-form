/*
 * 画面内通知ベル（管理画面の全ページで読み込む）
 * 上部バー右側にベルを差し込み、未対応（状態＝新規受注）の件数を赤バッジで表示する。
 * 1分ごとに自動更新し、開いている間に件数が増えたら小さなお知らせを出す。
 * ベル・お知らせを押すと受注一覧の「新規受注」タブへ移動する。
 * ★DBには一切触らない（既存の orders.status を数えるだけ）。
 */
(function () {
  if (window.__notifBellInit) return;
  window.__notifBellInit = true;

  var POLL_MS = 60000;
  var LINK = 'orders.html?status=new';
  var lastCount = null; // null＝まだ一度も取得していない（初回はお知らせを出さない）
  var user;
  try { user = JSON.parse(sessionStorage.getItem('user') || '{}'); } catch (e) { user = {}; }
  if (!user.tenantId) return; // 卸の管理画面以外（未ログイン・運営者画面）では何もしない

  function injectStyle() {
    if (document.getElementById('notif-bell-style')) return;
    var css =
      '.notif-bell{position:relative;display:inline-flex;align-items:center;justify-content:center;width:34px;height:34px;border-radius:10px;border:1px solid var(--border,#e5e7eb);background:var(--surface,#fff);cursor:pointer;color:var(--text-muted,#6b7280);transition:all 0.2s;text-decoration:none}' +
      '.notif-bell:hover{border-color:var(--orange,#ea580c);color:var(--orange,#ea580c)}' +
      '.notif-bell svg{width:18px;height:18px;stroke-width:1.75}' +
      '.notif-badge{position:absolute;top:-6px;right:-6px;min-width:18px;height:18px;padding:0 4px;border-radius:100px;background:#dc2626;color:#fff;font-size:11px;font-weight:700;line-height:18px;text-align:center;box-sizing:border-box;display:none}' +
      '.notif-badge.show{display:block}' +
      '.notif-toast{position:fixed;top:70px;right:20px;z-index:2000;background:#fff;border:1px solid var(--border,#e5e7eb);border-left:4px solid #dc2626;border-radius:12px;box-shadow:0 8px 24px rgba(0,0,0,0.12);padding:12px 16px;font-size:14px;color:var(--text,#111827);cursor:pointer;display:flex;align-items:center;gap:10px;max-width:320px}' +
      '.notif-toast .notif-toast-act{color:var(--orange,#ea580c);font-weight:600;white-space:nowrap}';
    var s = document.createElement('style');
    s.id = 'notif-bell-style';
    s.textContent = css;
    (document.head || document.documentElement).appendChild(s);
  }

  var BELL_SVG =
    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round">' +
    '<path d="M18 8a6 6 0 0 0-12 0c0 7-3 9-3 9h18s-3-2-3-9"/><path d="M13.73 21a2 2 0 0 1-3.46 0"/></svg>';

  function injectBell() {
    var userBox = document.querySelector('.topbar .topbar-user');
    if (!userBox || document.getElementById('notifBell')) return null;
    var a = document.createElement('a');
    a.id = 'notifBell';
    a.className = 'notif-bell';
    a.href = LINK;
    a.title = '未対応の注文（新規受注）';
    a.innerHTML = BELL_SVG + '<span class="notif-badge" id="notifBadge"></span>';
    userBox.insertBefore(a, userBox.firstChild);
    return a;
  }

  function setBadge(n) {
    var b = document.getElementById('notifBadge');
    if (!b) return;
    if (n > 0) {
      b.textContent = n > 99 ? '99+' : String(n);
      b.classList.add('show');
    } else {
      b.classList.remove('show');
    }
  }

  function showToast(n) {
    var old = document.getElementById('notifToast');
    if (old) old.remove();
    var t = document.createElement('div');
    t.id = 'notifToast';
    t.className = 'notif-toast';
    t.innerHTML = '<span>新しい注文が入りました（未対応 ' + n + '件）</span><span class="notif-toast-act">確認する →</span>';
    t.addEventListener('click', function () { location.href = LINK; });
    document.body.appendChild(t);
    setTimeout(function () { if (t.parentNode) t.remove(); }, 8000);
  }

  function refresh() {
    // 認証切れ等で取得できない時は静かに何もしない（画面本体の動きを邪魔しない）
    if (typeof getAccessToken !== 'function' || typeof SB_URL === 'undefined') return;
    var token = getAccessToken();
    if (!token) return;
    fetch(SB_URL + '/rest/v1/orders?tenant_id=eq.' + user.tenantId +
          '&status=eq.' + encodeURIComponent('新規受注') + '&select=id', {
      headers: {
        'apikey': SB_KEY,
        'Authorization': 'Bearer ' + token,
        'Prefer': 'count=exact',
        'Range': '0-0'
      }
    }).then(function (res) {
      if (!res.ok) return;
      var cr = res.headers.get('content-range') || '';
      var n = parseInt(cr.split('/')[1], 10);
      if (isNaN(n)) return;
      setBadge(n);
      if (lastCount !== null && n > lastCount) showToast(n);
      lastCount = n;
    }).catch(function () { /* 通信失敗時は次回の更新に任せる */ });
  }

  function start() {
    injectStyle();
    if (!injectBell()) return;
    refresh();
    setInterval(refresh, POLL_MS);
    document.addEventListener('visibilitychange', function () {
      if (!document.hidden) refresh();
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', start);
  } else {
    start();
  }
})();
