/*
 * 共通アップグレード案内モーダル（スタンダードプランのご案内）
 * 全管理画面（dashboard / quotation-list / customer / settings 等）で読み込み、
 * openUpgradeModal() を呼べば「どの画面からでも全く同じ案内」を表示する。
 *
 * ★ベネフィット文言と価格は「ここ1箇所」だけで定義する（各HTMLに直書きしない＝再ズレ防止）。
 *   価格の正＝コンテキスト/料金訴求ポリシー.md（スタンダード ¥19,800/月・税別）。
 */
(function () {
  if (window.__upgradeModalInit) return;
  window.__upgradeModalInit = true;

  var CSS = [
    '.upgrade-modal-overlay{position:fixed;inset:0;background:rgba(0,0,0,0.5);z-index:2000;display:none;align-items:center;justify-content:center;padding:24px;backdrop-filter:blur(4px)}',
    '.upgrade-modal-overlay.open{display:flex}',
    '.upgrade-modal{background:var(--surface,#fff);border-radius:16px;width:100%;max-width:440px;overflow:hidden;box-shadow:0 24px 64px rgba(0,0,0,0.2);animation:umModalIn 0.25s ease}',
    '@keyframes umModalIn{from{opacity:0;transform:scale(0.95) translateY(10px)}to{opacity:1;transform:scale(1) translateY(0)}}',
    '.upgrade-modal-header{background:linear-gradient(135deg,#e8630a,#f97316);padding:24px 28px;color:#fff}',
    '.upgrade-modal-title{font-size:17px;font-weight:700;margin-bottom:4px}',
    '.upgrade-modal-sub{font-size:14px;opacity:0.85}',
    '.upgrade-modal-body{padding:24px 28px}',
    '.upgrade-feature{display:flex;align-items:flex-start;gap:10px;margin-bottom:12px;font-size:14px}',
    '.upgrade-feature-icon{font-size:16px;flex-shrink:0;margin-top:1px}',
    '.upgrade-price{margin-top:16px;padding:14px 16px;background:var(--orange-pale,#fff4ec);border-radius:10px;border:1px solid rgba(232,99,10,0.2)}',
    '.upgrade-price-label{font-size:14px;color:var(--orange,#e8630a);font-weight:700;margin-bottom:4px}',
    '.upgrade-price-amount{font-size:22px;font-weight:700;font-family:"Space Grotesk",sans-serif}',
    '.upgrade-price-amount span{font-size:14px;font-weight:400;color:var(--text-muted,#7a6a55)}',
    '.upgrade-modal-footer{padding:16px 28px;border-top:1px solid var(--border,#e2d9ce);display:flex;gap:10px;justify-content:flex-end}',
    '.btn-upgrade{background:var(--orange,#e8630a);color:#fff;padding:10px 22px;border-radius:10px;border:none;font-size:14px;font-weight:700;cursor:pointer;font-family:"Noto Sans JP",sans-serif;transition:opacity 0.2s}',
    '.btn-upgrade:hover{opacity:0.85}',
    '.btn-later{background:var(--bg,#f7f3ee);color:var(--text-muted,#7a6a55);border:1.5px solid var(--border,#e2d9ce);padding:10px 18px;border-radius:10px;font-size:14px;font-weight:600;cursor:pointer;font-family:"Noto Sans JP",sans-serif}',
    '.btn-later:hover{border-color:var(--orange,#e8630a);color:var(--orange,#e8630a)}'
  ].join('');

  // スタンダードで解放されるベネフィット（順序固定・1箇所定義）
  var FEATURES = [
    ['🏢', '取引先数 無制限', 'スターター：10社まで → 無制限'],
    ['📄', '見積書の作成・発行', '取引先ごとの卸価格でPDF発行'],
    ['👥', '複数人ログイン', 'スタッフを招待して全員で使える'],
    ['📈', '売上の詳しいグラフ', '月次推移・商品別の分析']
  ];
  var PRICE_LABEL = 'スタンダードプラン';
  var PRICE_AMOUNT = '¥19,800';
  var PRICE_UNIT = '/月（税別）';

  function buildHtml() {
    var features = FEATURES.map(function (f) {
      return '<div class="upgrade-feature"><span class="upgrade-feature-icon">' + f[0] + '</span>' +
        '<div><strong>' + f[1] + '</strong><br>' +
        '<span style="color:var(--text-muted,#7a6a55);font-size:14px">' + f[2] + '</span></div></div>';
    }).join('');
    return '' +
      '<div class="upgrade-modal-overlay" id="upgradeModal" onclick="if(event.target===this)closeUpgradeModal()">' +
        '<div class="upgrade-modal">' +
          '<div class="upgrade-modal-header">' +
            '<div class="upgrade-modal-title">スタンダードプランにアップグレード</div>' +
            '<div class="upgrade-modal-sub">受注まわりをもっと楽に、もっとチームで</div>' +
          '</div>' +
          '<div class="upgrade-modal-body">' +
            features +
            '<div class="upgrade-price">' +
              '<div class="upgrade-price-label">' + PRICE_LABEL + '</div>' +
              '<div class="upgrade-price-amount">' + PRICE_AMOUNT + '<span>' + PRICE_UNIT + '</span></div>' +
            '</div>' +
          '</div>' +
          '<div class="upgrade-modal-footer">' +
            '<button class="btn-later" onclick="closeUpgradeModal()">後で</button>' +
            '<button class="btn-upgrade" onclick="location.href=\'contact.html?subject=upgrade\'">お問い合わせ →</button>' +
          '</div>' +
        '</div>' +
      '</div>';
  }

  function inject() {
    if (document.getElementById('upgradeModal')) return;
    if (!document.getElementById('upgrade-modal-style')) {
      var style = document.createElement('style');
      style.id = 'upgrade-modal-style';
      style.textContent = CSS;
      (document.head || document.documentElement).appendChild(style);
    }
    var wrap = document.createElement('div');
    wrap.innerHTML = buildHtml();
    document.body.appendChild(wrap.firstElementChild);
  }

  window.openUpgradeModal = function () {
    inject();
    var m = document.getElementById('upgradeModal');
    if (m) m.classList.add('open');
  };
  window.closeUpgradeModal = function () {
    var m = document.getElementById('upgradeModal');
    if (m) m.classList.remove('open');
  };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', inject);
  } else {
    inject();
  }
})();
