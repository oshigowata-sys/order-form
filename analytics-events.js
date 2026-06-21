/*
 * MeguRee — GA4 イベント計測（マーケLP共通）
 * 既存の挙動には一切干渉しない（capture フェーズで監視するだけ・preventDefault しない）。
 * gtag 本体（測定ID G-26ZR6LCJY2）は各ページの <head> で読み込み済みである前提。
 *
 * 送出イベント:
 *   - plan_select   : 料金プランのCTAクリック（plan_name）
 *   - cta_click     : 資料ダウンロード / お問い合わせ ページへの主要導線クリック（cta_label, cta_target）
 *   - contact_intent: 電話/メールリンクのクリック（method）※現状リンクは未設置・将来用
 */
(function () {
  function track(name, params) {
    if (typeof window.gtag === 'function') {
      window.gtag('event', name, params);
    }
  }

  function pageId() {
    var p = (location.pathname.split('/').pop() || '');
    return p || 'index.html';
  }

  function labelOf(el) {
    return (el.textContent || '').replace(/\s+/g, ' ').trim().slice(0, 60);
  }

  document.addEventListener('click', function (e) {
    var el = e.target.closest ? e.target.closest('a, button') : null;
    if (!el) return;

    // ① 料金プラン選択（lp.html のプランカード内CTA）
    var planCard = el.closest ? el.closest('.plan-card') : null;
    if (planCard && el.classList && el.classList.contains('btn-plan')) {
      var nameEl = planCard.querySelector('.plan-name');
      track('plan_select', {
        plan_name: nameEl ? nameEl.textContent.trim() : '',
        page: pageId()
      });
      return; // プランCTAは cta_click と二重計上しない
    }

    var href = (el.getAttribute && el.getAttribute('href')) || '';

    // ② 電話 / メールリンク（将来設置された場合に自動計測）
    if (href.indexOf('tel:') === 0) { track('contact_intent', { method: 'tel', page: pageId() }); return; }
    if (href.indexOf('mailto:') === 0) { track('contact_intent', { method: 'email', page: pageId() }); return; }

    // ③ 主要CTA（資料ダウンロード / お問い合わせ への遷移）
    if (/(^|\/)download\.html(\?|#|$)/.test(href)) {
      track('cta_click', { cta_label: labelOf(el), cta_target: 'download', page: pageId() });
      return;
    }
    if (/(^|\/)contact\.html(\?|#|$)/.test(href)) {
      track('cta_click', { cta_label: labelOf(el), cta_target: 'contact', page: pageId() });
      return;
    }
  }, true);
})();
