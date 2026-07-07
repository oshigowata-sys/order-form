/*
 * 画面内通知ベル（管理画面の全ページで読み込む）
 * 上部バー右側にベルを差し込み、未読（状態＝新規受注 かつ seen_at なし）の件数を赤バッジで表示する。
 * 1分ごとに自動更新し、開いている間に件数が増えたら小さなお知らせを出す。
 * ベルを押すとその場に新着一覧パネルが開き、1件押すとその注文の詳細へ直行する
 * （orders.html?open=<受注ID>）。詳細を開くと orders.html 側が seen_at を記録＝既読になり数が減る。
 * パネルは未読＝薄いオレンジ／既読＝白で色分け。「すべて見る」で受注一覧の「新規受注」タブへ。
 */
(function () {
  if (window.__notifBellInit) return;
  window.__notifBellInit = true;

  var POLL_MS = 60000;
  var LINK = 'orders.html?status=new';
  var PANEL_LIMIT = 10;
  var lastCount = null; // null＝まだ一度も取得していない（初回はお知らせを出さない）
  var user;
  try { user = JSON.parse(sessionStorage.getItem('user') || '{}'); } catch (e) { user = {}; }
  if (!user.tenantId) return; // 卸の管理画面以外（未ログイン・運営者画面）では何もしない

  function esc(s) {
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }

  function injectStyle() {
    if (document.getElementById('notif-bell-style')) return;
    var css =
      '.notif-bell{position:relative;display:inline-flex;align-items:center;justify-content:center;width:34px;height:34px;border-radius:10px;border:1px solid var(--border,#e5e7eb);background:var(--surface,#fff);cursor:pointer;color:var(--text-muted,#6b7280);transition:all 0.2s;text-decoration:none}' +
      '.notif-bell:hover{border-color:var(--orange,#ea580c);color:var(--orange,#ea580c)}' +
      '.notif-bell svg{width:18px;height:18px;stroke-width:1.75}' +
      '.notif-badge{position:absolute;top:-6px;right:-6px;min-width:18px;height:18px;padding:0 4px;border-radius:100px;background:#dc2626;color:#fff;font-size:11px;font-weight:700;line-height:18px;text-align:center;box-sizing:border-box;display:none}' +
      '.notif-badge.show{display:block}' +
      '.notif-toast{position:fixed;top:70px;right:20px;z-index:2000;background:#fff;border:1px solid var(--border,#e5e7eb);border-left:4px solid #dc2626;border-radius:12px;box-shadow:0 8px 24px rgba(0,0,0,0.12);padding:12px 16px;font-size:14px;color:var(--text,#111827);cursor:pointer;display:flex;align-items:center;gap:10px;max-width:320px}' +
      '.notif-toast .notif-toast-act{color:var(--orange,#ea580c);font-weight:600;white-space:nowrap}' +
      '.notif-panel{position:absolute;top:calc(100% + 8px);right:0;z-index:2000;width:320px;background:#fff;border:1px solid var(--border,#e5e7eb);border-radius:14px;box-shadow:0 12px 32px rgba(0,0,0,0.12);overflow:hidden;display:none}' +
      '.notif-panel.show{display:block}' +
      '.notif-panel-head{padding:12px 16px 10px;font-size:12px;font-weight:700;color:var(--text-muted,#6b7280);letter-spacing:0.5px;border-bottom:1px solid var(--border,#e5e7eb)}' +
      '.notif-panel-list{max-height:320px;overflow-y:auto}' +
      '.notif-item{display:block;width:100%;text-align:left;padding:11px 16px;border:0;border-bottom:1px solid var(--border,#e5e7eb);background:none;cursor:pointer;font-family:inherit;text-decoration:none}' +
      '.notif-item:hover{background:var(--bg,#f9fafb)}' +
      '.notif-item.unread{background:#fff7ed}' +
      '.notif-item.unread:hover{background:#ffedd5}' +
      '.notif-item:last-child{border-bottom:0}' +
      '.notif-item-title{font-size:14px;font-weight:600;color:var(--text,#111827)}' +
      '.notif-item-sub{margin-top:2px;font-size:12px;color:var(--text-muted,#6b7280)}' +
      '.notif-panel-empty{padding:24px 16px;text-align:center;font-size:13px;color:var(--text-muted,#6b7280)}' +
      '.notif-panel-all{display:block;padding:11px 16px;text-align:center;font-size:13px;font-weight:600;color:var(--orange,#ea580c);text-decoration:none;border-top:1px solid var(--border,#e5e7eb);background:#fff}' +
      '.notif-panel-all:hover{background:var(--bg,#f9fafb)}';
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
    // パネルをベルの右下に出すための位置基準
    if (!userBox.style.position) userBox.style.position = 'relative';
    var a = document.createElement('a');
    a.id = 'notifBell';
    a.className = 'notif-bell';
    a.href = LINK; // JS無効・中クリック時の逃げ道
    a.title = '未対応の注文（新規受注）';
    a.innerHTML = BELL_SVG + '<span class="notif-badge" id="notifBadge"></span>';
    a.addEventListener('click', function (ev) {
      ev.preventDefault();
      togglePanel();
    });
    userBox.insertBefore(a, userBox.firstChild);

    var panel = document.createElement('div');
    panel.id = 'notifPanel';
    panel.className = 'notif-panel';
    panel.innerHTML =
      '<div class="notif-panel-head">新規受注</div>' +
      '<div class="notif-panel-list" id="notifPanelList"></div>' +
      '<a class="notif-panel-all" href="' + LINK + '">すべて見る →</a>';
    userBox.appendChild(panel);

    // パネルの外を押したら閉じる（ベル自身は togglePanel に任せる）
    document.addEventListener('click', function (ev) {
      var p = document.getElementById('notifPanel');
      if (!p || !p.classList.contains('show')) return;
      if (p.contains(ev.target) || a.contains(ev.target)) return;
      p.classList.remove('show');
    });
    document.addEventListener('keydown', function (ev) {
      if (ev.key === 'Escape') {
        var p = document.getElementById('notifPanel');
        if (p) p.classList.remove('show');
      }
    });
    return a;
  }

  function togglePanel() {
    var p = document.getElementById('notifPanel');
    if (!p) return;
    if (p.classList.contains('show')) {
      p.classList.remove('show');
    } else {
      p.classList.add('show');
      loadPanel();
    }
  }

  // 受注日 YYYY-MM-DD → M/D
  function fmtDate(d) {
    var parts = String(d || '').split('-');
    return parts.length >= 3 ? (Number(parts[1]) + '/' + Number(parts[2])) : esc(String(d || ''));
  }

  function loadPanel() {
    var list = document.getElementById('notifPanelList');
    if (!list) return;
    list.innerHTML = '<div class="notif-panel-empty">読み込み中...</div>';
    if (typeof getAccessToken !== 'function' || typeof SB_URL === 'undefined') {
      list.innerHTML = '<div class="notif-panel-empty">読み込めませんでした</div>';
      return;
    }
    var token = getAccessToken();
    if (!token) {
      list.innerHTML = '<div class="notif-panel-empty">読み込めませんでした</div>';
      return;
    }
    // 新着＝状態が「新規受注」の注文を、未読（seen_atなし）優先＋新しい順に。
    // 金額は画面ごとの計算ルールに任せ、ここでは出さない
    fetch(SB_URL + '/rest/v1/orders?tenant_id=eq.' + user.tenantId +
          '&status=eq.' + encodeURIComponent('新規受注') +
          '&select=id,order_code,order_date,seen_at,input_company_name,customers(company_name),order_items(quantity)' +
          '&order=seen_at.desc.nullsfirst,order_date.desc,created_at.desc&limit=' + PANEL_LIMIT, {
      headers: { 'apikey': SB_KEY, 'Authorization': 'Bearer ' + token }
    }).then(function (res) {
      if (!res.ok) throw new Error('HTTP ' + res.status);
      return res.json();
    }).then(function (rows) {
      if (!rows || !rows.length) {
        list.innerHTML = '<div class="notif-panel-empty">未対応の新規受注はありません</div>';
        return;
      }
      list.innerHTML = rows.map(function (o) {
        var name = (o.customers && o.customers.company_name) || o.input_company_name || '（取引先不明）';
        var qty = (o.order_items || []).reduce(function (s, it) { return s + (Number(it.quantity) || 0); }, 0);
        var unread = o.seen_at == null;
        return '<a class="notif-item' + (unread ? ' unread' : '') + '" href="orders.html?open=' + encodeURIComponent(o.id) + '">' +
               '<div class="notif-item-title">' + esc(name) + ' から新規注文</div>' +
               '<div class="notif-item-sub">' + fmtDate(o.order_date) + '・商品' + qty + '点・' + esc(o.order_code || '') + '</div>' +
               '</a>';
      }).join('');
    }).catch(function () {
      list.innerHTML = '<div class="notif-panel-empty">読み込めませんでした</div>';
    });
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
    // 未読＝状態が「新規受注」かつ既読記録（seen_at）なし
    fetch(SB_URL + '/rest/v1/orders?tenant_id=eq.' + user.tenantId +
          '&status=eq.' + encodeURIComponent('新規受注') + '&seen_at=is.null&select=id', {
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
    // 詳細を開いて既読にした直後、orders.html からバッジを即時更新できるように公開
    window.__notifBellRefresh = refresh;
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
