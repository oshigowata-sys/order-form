/**
 * MeguRee リアルタイム印刷プレビュー共通レンダラー
 *
 * orders.html（受注新規・編集）と quotation.html（見積書編集）で使用する
 * 「縮小プレビュー版」のHTMLビルダー。
 *
 * 既存の invoice.html / quotation.html の本番印刷物用レンダラーとは独立しており、
 * 既発行帳票・印刷レイアウトの見た目には一切影響しない。
 *
 * Public API:
 *   MeguReePreview.renderOrder(targetEl, data)
 *     -> data から「納品書 + 請求書」のミニプレビューを描画
 *   MeguReePreview.renderQuotation(targetEl, data)
 *     -> data から「見積書」のミニプレビューを描画
 *
 * data shape:
 *   {
 *     customer:    { company_name, contact_name, postal_code, address, phone },
 *     settings:    { name, person, postal_code, address, tel, fax, invoice_num },
 *     bankAccounts:[{ bank_name, branch_name, account_type, account_number, account_holder }],
 *     items: [{
 *       product_code, product_name, quantity, unit_price, is_food, remarks,
 *       list_price?, case_quantity?, jan_code?
 *     }],
 *     orderId?, deliveryDate?, invoiceNumber?, issuedDate?, dueDate?,
 *     quotationNumber?, expiryLabel?, notes?
 *   }
 */
(function(global) {
  'use strict';

  const CSS_ID = 'mini-preview-styles';
  function injectStyles() {
    if (document.getElementById(CSS_ID)) return;
    const style = document.createElement('style');
    style.id = CSS_ID;
    style.textContent = `
      .mini-preview-wrap {
        background:#fff;border:1px solid #e2d9ce;border-radius:12px;
        padding:18px;font-family:'Noto Sans JP',sans-serif;color:#1a1208;
        font-size:11px;line-height:1.5;overflow:hidden;
      }
      .mini-preview-sheet + .mini-preview-sheet {
        margin-top:20px;padding-top:18px;border-top:2px dashed #ccc;
      }
      .mini-preview-header {
        display:flex;justify-content:space-between;align-items:flex-start;
        margin-bottom:12px;padding-bottom:10px;border-bottom:2px solid #1a1208;
      }
      .mini-preview-title-block{display:flex;flex-direction:column}
      .mini-preview-title{
        font-size:22px;font-weight:700;font-family:'Noto Serif JP',serif;letter-spacing:4px;
      }
      .mini-preview-subtitle{
        font-size:9px;letter-spacing:2px;color:#7a6a55;text-transform:uppercase;margin-top:2px;
      }
      .mini-preview-meta table{font-size:10px;border-collapse:collapse}
      .mini-preview-meta td{padding:2px 6px;vertical-align:top}
      .mini-preview-meta td:first-child{color:#7a6a55;font-weight:600}
      .mini-preview-meta td:last-child{font-weight:600;font-family:'Space Grotesk',sans-serif}
      .mini-preview-parties{
        display:flex;justify-content:space-between;gap:16px;
        margin-bottom:12px;align-items:flex-start;
      }
      .mini-preview-to{flex:1;min-width:0}
      .mini-preview-from{text-align:right;max-width:55%}
      .mini-preview-label{
        font-size:8px;letter-spacing:2px;color:#7a6a55;
        text-transform:uppercase;margin-bottom:4px;
      }
      .mini-preview-name{
        font-size:14px;font-weight:700;font-family:'Noto Serif JP',serif;line-height:1.4;
        word-break:break-word;
      }
      .mini-preview-name-suffix{
        font-size:0.75em;color:#7a6a55;font-weight:500;margin-left:4px;
      }
      .mini-preview-line{font-size:11px;color:#7a6a55;line-height:1.5;word-break:break-word}
      .mini-preview-line.bold{color:#1a1208;font-weight:600}
      .mini-preview-table{width:100%;border-collapse:collapse;font-size:10px;margin-bottom:8px}
      .mini-preview-table th{
        background:#f7f3ee;color:#7a6a55;padding:4px 6px;font-weight:700;
        text-align:left;border-bottom:1px solid #e2d9ce;white-space:nowrap;
      }
      .mini-preview-table td{padding:3px 6px;border-bottom:1px solid #f0e8dd;vertical-align:middle}
      .mini-preview-table td.num{text-align:right;font-family:'Space Grotesk',sans-serif}
      .mini-preview-table td.code{font-family:'Space Grotesk',sans-serif;color:#7a6a55;font-size:9px}
      .mini-preview-table td.muted{color:#7a6a55;font-size:9px}
      .mini-preview-table tr.total-row td{font-weight:700;background:#f7f3ee}
      .mini-preview-table tr.grand-row td{
        font-weight:700;font-size:13px;background:#fff4ec;color:#e8630a;
      }
      .mini-preview-empty{
        padding:30px 20px;text-align:center;color:#aaa;font-size:12px;
      }
      .mini-preview-amount-headline{
        background:#1a1208;color:#fff;padding:10px 14px;border-radius:8px;
        display:flex;justify-content:space-between;align-items:center;margin-bottom:12px;
      }
      .mini-preview-amount-headline-label{font-size:11px;letter-spacing:1px}
      .mini-preview-amount-headline-value{
        font-size:18px;font-weight:700;font-family:'Space Grotesk',sans-serif;
      }
      .mini-preview-note{color:#aaa;font-style:italic}
      .mini-preview-undecided{color:#aaa}
      .mini-preview-bank{
        background:#f7f3ee;border:1px solid #e2d9ce;border-radius:6px;
        padding:6px 10px;font-size:10px;margin-bottom:8px;
      }
      .mini-preview-bank-label{
        font-size:8px;letter-spacing:2px;color:#7a6a55;
        text-transform:uppercase;margin-bottom:4px;
      }
      .mini-preview-notes{
        margin-top:8px;padding:8px;background:#f7f3ee;
        border-radius:6px;font-size:10px;line-height:1.4;color:#1a1208;
      }
      .mini-preview-totals-row{display:flex;gap:6px;align-items:stretch;margin-top:4px}
      .mini-preview-totals-notes{flex:1;border:1px solid #e2d9ce;border-radius:4px;padding:5px 7px;background:#fff;font-size:9px;line-height:1.4;color:#1a1208;min-height:42px;white-space:pre-wrap}
      .mini-preview-totals-notes-label{font-size:7px;letter-spacing:1px;color:#7a6a55;text-transform:uppercase;margin-bottom:2px}
      .mini-preview-totals-table{width:160px;border-collapse:collapse;font-size:9px;flex-shrink:0}
      .mini-preview-totals-table td{border:1px solid #e2d9ce;padding:3px 6px}
      .mini-preview-totals-table td:first-child{background:#faf8f5;color:#7a6a55;width:72px}
      .mini-preview-totals-table td:last-child{text-align:right;font-family:'Space Grotesk',sans-serif}
      .mini-preview-totals-table tr.grand-row td{font-weight:700;background:#fff;color:#1a1208}
    `;
    document.head.appendChild(style);
  }

  function esc(s) {
    return String(s == null ? '' : s)
      .replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;')
      .replace(/"/g,'&quot;').replace(/'/g,'&#39;');
  }
  function fmtYen(n) {
    const v = Number(n || 0);
    return v < 0 ? '-¥' + Math.abs(v).toLocaleString('ja-JP') : '¥' + v.toLocaleString('ja-JP');
  }
  function fmtJa(dateStr) {
    if (!dateStr) return '';
    const d = new Date(dateStr);
    if (isNaN(d.getTime())) return String(dateStr);
    return d.getFullYear() + '年' + (d.getMonth() + 1) + '月' + d.getDate() + '日';
  }
  function formatZip(zip) {
    if (!zip) return '';
    const digits = String(zip).replace(/[^0-9]/g, '');
    return digits.length === 7
      ? '〒' + digits.slice(0, 3) + '-' + digits.slice(3)
      : '〒' + String(zip);
  }
  function formatJan(jan) {
    if (!jan) return '';
    const digits = String(jan).replace(/[^0-9]/g, '');
    if (digits.length === 13) {
      return digits.slice(0,1) + ' ' + digits.slice(1,7) + ' ' + digits.slice(7);
    }
    return digits;
  }

  function buildFromBlock(s) {
    if (!s || !s.name) {
      return '<div class="mini-preview-note">⚙ 発行者情報を設定してください</div>';
    }
    const telDigits = String(s.tel || '').replace(/[^0-9]/g, '');
    const faxDigits = String(s.fax || '').replace(/[^0-9]/g, '');
    const sameTelFax = telDigits && faxDigits && telDigits === faxDigits;
    let contactLine = '';
    if (sameTelFax) contactLine = `<div class="mini-preview-line">TEL／FAX: ${esc(s.tel)}</div>`;
    else if (s.tel && s.fax) contactLine = `<div class="mini-preview-line">TEL: ${esc(s.tel)} ／ FAX: ${esc(s.fax)}</div>`;
    else if (s.tel) contactLine = `<div class="mini-preview-line">TEL: ${esc(s.tel)}</div>`;
    else if (s.fax) contactLine = `<div class="mini-preview-line">FAX: ${esc(s.fax)}</div>`;

    const zipLine = s.postal_code ? `<div class="mini-preview-line">${esc(formatZip(s.postal_code))}</div>` : '';
    const addrLine = s.address ? `<div class="mini-preview-line">${esc(s.address)}</div>` : '';
    const personLine = s.person ? `<div class="mini-preview-line bold">${esc(s.person)}</div>` : '';
    const invoiceLine = s.invoice_num ? `<div class="mini-preview-line" style="margin-top:3px;font-size:10px">適格請求書番号: ${esc(s.invoice_num)}</div>` : '';

    return `
      <div class="mini-preview-name">${esc(s.name)}</div>
      ${personLine}
      ${zipLine}
      ${addrLine}
      ${contactLine}
      ${invoiceLine}
    `;
  }

  function buildToBlock(c, suffix) {
    const hasName = c && (c.company_name || c.name);
    if (!hasName) {
      return '<div class="mini-preview-note">取引先を選択してください</div>';
    }
    const nameStr = c.company_name || c.name;
    const person = (c.contact_name || c.person) ? `<div class="mini-preview-line">${esc(c.contact_name || c.person)} 様</div>` : '';
    const zip = c.postal_code ? `<div class="mini-preview-line">${esc(formatZip(c.postal_code))}</div>` : '';
    const addr = c.address ? `<div class="mini-preview-line">${esc(c.address)}</div>` : '';
    const phone = (c.phone || c.tel) ? `<div class="mini-preview-line">TEL: ${esc(c.phone || c.tel)}</div>` : '';

    return `
      <div class="mini-preview-name">${esc(nameStr)}${suffix ? `<span class="mini-preview-name-suffix">${esc(suffix)}</span>` : ''}</div>
      ${person}
      ${zip}
      ${addr}
      ${phone}
    `;
  }

  // 個人取引：税込み単価そのまま／卸取引：税抜き単価そのまま。換算なし。
  function toDispPrice(price, _isFood, _isPersonal) {
    return Math.round(price);
  }
  // 税率マーク：
  //   個人取引（税込み単価表示）：軽減='ケコ'（軽減税率込）/ 標準='コ'（税込）
  //   得意先取引（税抜き単価表示）：軽減='ケ'（軽減税率）/ 標準=''（マーク無し）
  function taxMark(isFood, isPersonal) {
    if (isPersonal) return isFood ? 'ケコ' : 'コ';
    return isFood ? 'ケ' : '';
  }

  function calcTotals(items, handlingFee, shippingFee, isPersonal, handlingCharge, shippingCharge) {
    let sum8 = 0, sum10 = 0;
    for (const it of items) {
      const qty = Number(it.quantity || 0);
      const price = Number(it.unit_price || 0);
      if (price === 0) continue;
      const sub = qty * price;
      if (it.is_food) sum8 += sub;
      else sum10 += sub;
    }
    // 手数料・送料は税込で入力された最終金額。消費税は計算せず、合計（税込）にそのまま加減算する。
    const hSign = handlingCharge ? 1 : -1;
    const sSign = shippingCharge ? 1 : -1;
    const feeIncl = hSign * (Number(handlingFee) || 0) + sSign * (Number(shippingFee) || 0);
    if (isPersonal) {
      // 個人取引：消費税計算なし。送料も税込のまま合計に加算。
      return {
        excl8: sum8, excl10: sum10, subtotal: sum8 + sum10,
        tax8: 0, tax10: 0, tax: 0,
        total: sum8 + sum10 + feeIncl,
        incl8: sum8, incl10: sum10,
      };
    }
    // 卸取引（外税）：商品にのみ課税。送料・手数料は税込なので税計算せず合計に加減算（消費税の行に出さない）。
    const tax8 = Math.round(sum8 * 0.08);
    const tax10 = Math.round(sum10 * 0.10);
    const subtotal = sum8 + sum10;
    return {
      excl8: sum8, excl10: sum10, subtotal,
      tax8, tax10, tax: tax8 + tax10,
      total: subtotal + tax8 + tax10 + feeIncl,
      incl8: sum8 + tax8, incl10: sum10 + tax10,
    };
  }

  function buildTotalsRows(t, isPersonal, grandLabel) {
    const grand = grandLabel || '合計（税込）';
    if (isPersonal) {
      const rows = [];
      if (t.excl8 !== 0)  rows.push(`<tr><td>8%軽減込ケコ</td><td>${fmtYen(t.excl8)}</td></tr>`);
      if (t.excl10 !== 0) rows.push(`<tr><td>10%対象込コ</td><td>${fmtYen(t.excl10)}</td></tr>`);
      rows.push(`<tr class="grand-row"><td>${grand}</td><td>${fmtYen(t.total)}</td></tr>`);
      return rows.join('');
    }
    return `
      <tr><td>税抜合計</td><td>${fmtYen(t.subtotal)}</td></tr>
      ${t.tax8 !== 0 ? `<tr><td>消費税（8%）</td><td>${fmtYen(t.tax8)}</td></tr>` : ''}
      ${t.tax10 !== 0 ? `<tr><td>消費税（10%）</td><td>${fmtYen(t.tax10)}</td></tr>` : ''}
      <tr class="grand-row"><td>${grand}</td><td>${fmtYen(t.total)}</td></tr>`;
  }

  function buildFeeRows(handlingFee, shippingFee, isPersonal, handlingCharge, shippingCharge, handlingQty, shippingQty) {
    const rows = [];
    const fmtFee = (label, fee, charge, qty) => {
      const q = Number(qty) || 1;
      const unit = (charge ? 1 : -1) * Math.abs(Number(fee) || 0);
      const line = unit * q;
      return `<tr>
        <td class="code">—</td>
        <td>${label}</td>
        <td class="num">${q}</td>
        <td class="num">${fmtYen(unit)}<span style="margin-left:3px;color:#7a6a55">${taxMark(false, isPersonal)}</span></td>
        <td class="num">${fmtYen(line)}</td>
        <td class="muted" style="text-align:center">税込</td>
        <td class="muted"></td>
      </tr>`;
    };
    if ((Number(handlingFee) || 0) > 0) rows.push(fmtFee('手数料', handlingFee, handlingCharge, handlingQty));
    if ((Number(shippingFee) || 0) > 0) rows.push(fmtFee('送料', shippingFee, shippingCharge, shippingQty));
    return rows.join('');
  }

  // firstCellHtml: 先頭列の<td>を差し替えたい時に指定（納品書・請求書とも上代）
  function buildOrderItemRow(it, isPersonal, firstCellHtml) {
    const qty = Number(it.quantity || 0);
    const price = Number(it.unit_price || 0);
    const sub = qty * price;
    const isReq = price === 0;
    const priceCell = isReq ? '<span style="color:#dc2626">要相談</span>' : `${fmtYen(price)}<span style="margin-left:3px;color:#7a6a55">${taxMark(!!it.is_food, isPersonal)}</span>`;
    const subCell = isReq ? '<span style="color:#dc2626">要相談</span>' : fmtYen(sub);
    return `<tr>
      ${firstCellHtml || `<td class="code">${esc(it.product_code || '—')}</td>`}
      <td>${esc(it.product_name || '-')}</td>
      <td class="num">${qty.toLocaleString()}</td>
      <td class="num">${priceCell}</td>
      <td class="num">${subCell}</td>
      <td class="muted" style="text-align:center">${it.is_food ? '8%' : '10%'}</td>
      <td class="muted" style="max-width:80px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">${esc(it.remarks || '')}</td>
    </tr>`;
  }

  function buildDeliveryHTML(data) {
    const items = data.items || [];
    const c = data.customer || {};
    const s = data.settings || {};
    const isPersonal = !!data.isPersonalTrade;
    const handlingFee = Number(data.handlingFee) || 0;
    const shippingFee = Number(data.shippingFee) || 0;
    const handlingCharge = !!data.handlingCharge;
    const shippingCharge = !!data.shippingCharge;
    const handlingQty = Number(data.handlingQty) || 1;
    const shippingQty = Number(data.shippingQty) || 1;
    const totals = calcTotals(items, handlingFee * handlingQty, shippingFee * shippingQty, isPersonal, handlingCharge, shippingCharge);

    const deliveryLabel = data.deliveryDate ? fmtJa(data.deliveryDate) : fmtJa(new Date());
    const orderIdLabel = data.orderId ? esc(data.orderId) : '<span class="mini-preview-undecided">（未確定）</span>';

    // 納品書プレビューの先頭列は上代（実物 invoice.html の納品書と同じ）。未設定は「—」。
    const listPriceCell = it => `<td class="num">${it.list_price != null ? fmtYen(it.list_price) : '—'}</td>`;
    const itemRows = items.length > 0
      ? items.map(it => buildOrderItemRow(it, isPersonal, listPriceCell(it))).join('') + buildFeeRows(handlingFee, shippingFee, isPersonal, handlingCharge, shippingCharge, handlingQty, shippingQty)
      : '<tr><td colspan="7" class="mini-preview-empty">明細データがありません</td></tr>';
    const dataRows = itemRows;

    return `
      <div class="mini-preview-sheet">
        <div class="mini-preview-header">
          <div class="mini-preview-title-block">
            <div class="mini-preview-title">納 品 書</div>
            <div class="mini-preview-subtitle">DELIVERY NOTE</div>
          </div>
          <div class="mini-preview-meta">
            <table>
              <tr><td>納品日</td><td>${deliveryLabel}</td></tr>
              <tr><td>受注ID</td><td>${orderIdLabel}</td></tr>
            </table>
          </div>
        </div>
        <div class="mini-preview-parties">
          <div class="mini-preview-to">
            <div class="mini-preview-label">納品先 / DELIVER TO</div>
            ${buildToBlock(c, '御中')}
          </div>
          <div class="mini-preview-from">
            <div class="mini-preview-label">発行者 / ISSUED BY</div>
            ${buildFromBlock(s)}
          </div>
        </div>
        <table class="mini-preview-table">
          <thead><tr>
            <th style="text-align:center">上代</th><th>商品名</th>
            <th style="text-align:center">数量</th>
            <th style="text-align:center">単価</th>
            <th style="text-align:center">金額</th>
            <th style="text-align:center">税率</th>
            <th>備考</th>
          </tr></thead>
          <tbody>${dataRows}</tbody>
        </table>
        <div class="mini-preview-totals-row">
          <div class="mini-preview-totals-notes">
            <div class="mini-preview-totals-notes-label">備考 / NOTES</div>
            ${data.notes ? esc(data.notes).replace(/\n/g,'<br>') : ''}
          </div>
          <table class="mini-preview-totals-table">
            ${buildTotalsRows(totals, isPersonal, '合計（税込）')}
          </table>
        </div>
      </div>
    `;
  }

  function buildInvoiceHTML(data) {
    const items = data.items || [];
    const c = data.customer || {};
    const s = data.settings || {};
    const banks = data.bankAccounts || [];
    const isPersonal = !!data.isPersonalTrade;
    const handlingFee = Number(data.handlingFee) || 0;
    const shippingFee = Number(data.shippingFee) || 0;
    const handlingCharge = !!data.handlingCharge;
    const shippingCharge = !!data.shippingCharge;
    const handlingQty = Number(data.handlingQty) || 1;
    const shippingQty = Number(data.shippingQty) || 1;
    const totals = calcTotals(items, handlingFee * handlingQty, shippingFee * shippingQty, isPersonal, handlingCharge, shippingCharge);

    const invoiceNumLabel = data.invoiceNumber || '<span class="mini-preview-undecided">（未確定）</span>';
    const issuedLabel = data.issuedDate ? fmtJa(data.issuedDate) : fmtJa(new Date());
    const dueLabel = data.dueDate ? fmtJa(data.dueDate) : '<span class="mini-preview-undecided">（未確定）</span>';

    // 請求書プレビューの先頭列も上代（実物 invoice.html の請求書と同じ）。未設定は「—」。
    const listPriceCell = it => `<td class="num">${it.list_price != null ? fmtYen(it.list_price) : '—'}</td>`;
    const dataRows = items.length > 0
      ? items.map(it => buildOrderItemRow(it, isPersonal, listPriceCell(it))).join('') + buildFeeRows(handlingFee, shippingFee, isPersonal, handlingCharge, shippingCharge, handlingQty, shippingQty)
      : '<tr><td colspan="7" class="mini-preview-empty">明細データがありません</td></tr>';

    const bankBlock = banks.length > 0
      ? banks.map(b => {
          const parts = [];
          if (b.bank_name) parts.push(esc(b.bank_name));
          if (b.branch_name) parts.push(esc(b.branch_name));
          if (b.account_type) parts.push(esc(b.account_type));
          if (b.account_number) parts.push(esc(b.account_number));
          if (b.account_holder) parts.push(`名義: ${esc(b.account_holder)}`);
          return parts.join(' / ');
        }).join(' ／ ')
      : '<span class="mini-preview-undecided">（未設定）</span>';

    return `
      <div class="mini-preview-sheet">
        <div class="mini-preview-header">
          <div class="mini-preview-title-block">
            <div class="mini-preview-title">請 求 書</div>
            <div class="mini-preview-subtitle">INVOICE</div>
          </div>
          <div class="mini-preview-meta">
            <table>
              <tr><td>請求書番号</td><td>${invoiceNumLabel}</td></tr>
              <tr><td>発行日</td><td>${issuedLabel}</td></tr>
              <tr><td>支払期限</td><td>${dueLabel}</td></tr>
            </table>
          </div>
        </div>
        <div class="mini-preview-parties">
          <div class="mini-preview-to">
            <div class="mini-preview-label">請求先 / BILL TO</div>
            ${buildToBlock(c)}
          </div>
          <div class="mini-preview-from">
            <div class="mini-preview-label">発行者 / ISSUED BY</div>
            ${buildFromBlock(s)}
          </div>
        </div>
        <div class="mini-preview-bank">
          <div class="mini-preview-bank-label">お振込先 / BANK TRANSFER</div>
          ${bankBlock}
        </div>
        <table class="mini-preview-table">
          <thead><tr>
            <th style="text-align:center">上代</th><th>商品名</th>
            <th style="text-align:center">数量</th>
            <th style="text-align:center">単価</th>
            <th style="text-align:center">金額</th>
            <th style="text-align:center">税率</th>
            <th>備考</th>
          </tr></thead>
          <tbody>${dataRows}</tbody>
        </table>
        <div class="mini-preview-totals-row">
          <div class="mini-preview-totals-notes">
            <div class="mini-preview-totals-notes-label">備考 / NOTES</div>
            ${data.notes ? esc(data.notes).replace(/\n/g,'<br>') : ''}
          </div>
          <table class="mini-preview-totals-table">
            ${buildTotalsRows(totals, isPersonal, '今回御請求額（税込）')}
          </table>
        </div>
      </div>
    `;
  }

  function buildQuotationHTML(data) {
    const items = data.items || [];
    const c = data.customer || {};
    const s = data.settings || {};
    const isPersonal = !!data.isPersonalTrade;
    const handlingFee = Number(data.handlingFee) || 0;
    const shippingFee = Number(data.shippingFee) || 0;
    const handlingCharge = !!data.handlingCharge;
    const shippingCharge = !!data.shippingCharge;
    const handlingQty = Number(data.handlingQty) || 1;
    const shippingQty = Number(data.shippingQty) || 1;
    const totals = calcTotals(items, handlingFee * handlingQty, shippingFee * shippingQty, isPersonal, handlingCharge, shippingCharge);

    const numberLabel = data.quotationNumber || '<span class="mini-preview-undecided">（保存時に自動採番）</span>';
    const issuedLabel = data.issuedDate ? fmtJa(data.issuedDate) : fmtJa(new Date());
    const expiryLabel = data.expiryLabel || '<span class="mini-preview-undecided">（未確定）</span>';

    const buildQItem = it => {
      const qty = Number(it.quantity || 0);
      const price = Number(it.unit_price || 0);
      const dispPrice = toDispPrice(price, !!it.is_food, isPersonal);
      const subDisp = qty * dispPrice;
      const isReq = price === 0;
      const priceCell = isReq ? '<span style="color:#dc2626">要相談</span>' : `${fmtYen(dispPrice)}<span style="margin-left:3px;color:#7a6a55">${taxMark(!!it.is_food, isPersonal)}</span>`;
      const subCell = isReq ? '<span style="color:#dc2626">要相談</span>' : fmtYen(subDisp);
      return `<tr>
        <td class="num" style="width:60px">${it.list_price != null ? fmtYen(it.list_price) : '—'}</td>
        <td>${esc(it.product_name || '-')}</td>
        <td class="num" style="width:45px">${it.case_quantity != null ? Number(it.case_quantity).toLocaleString() : '—'}</td>
        <td class="num" style="width:40px">${qty.toLocaleString()}</td>
        <td class="num" style="width:65px">${priceCell}</td>
        <td class="num" style="width:75px">${subCell}</td>
        <td class="code" style="width:90px">${it.jan_code ? esc(formatJan(it.jan_code)) : '—'}</td>
      </tr>`;
    };
    const buildQFeeRow = (label, fee, charge, qty) => {
      const q = Number(qty) || 1;
      const unit = toDispPrice((charge ? 1 : -1) * Math.abs(Number(fee) || 0), false, isPersonal);
      const line = unit * q;
      return `<tr>
        <td class="num" style="width:60px">—</td>
        <td>${label}</td>
        <td class="num" style="width:45px">—</td>
        <td class="num" style="width:40px">${q}</td>
        <td class="num" style="width:65px">${fmtYen(unit)}<span style="margin-left:3px;color:#7a6a55">${taxMark(false, isPersonal)}</span></td>
        <td class="num" style="width:75px">${fmtYen(line)}</td>
        <td class="code" style="width:90px">—</td>
      </tr>`;
    };
    let feeRowsQ = '';
    if (handlingFee > 0) feeRowsQ += buildQFeeRow('手数料', handlingFee, handlingCharge, handlingQty);
    if (shippingFee > 0) feeRowsQ += buildQFeeRow('送料', shippingFee, shippingCharge, shippingQty);

    const dataRows = items.length > 0
      ? items.map(buildQItem).join('') + feeRowsQ
      : '<tr><td colspan="7" class="mini-preview-empty">明細データがありません</td></tr>';

    return `
      <div class="mini-preview-sheet">
        <div class="mini-preview-header">
          <div class="mini-preview-title-block">
            <div class="mini-preview-title">お見積書</div>
            <div class="mini-preview-subtitle">QUOTATION</div>
          </div>
          <div class="mini-preview-meta">
            <table>
              <tr><td>見積番号</td><td>${numberLabel}</td></tr>
              <tr><td>発行日</td><td>${issuedLabel}</td></tr>
              <tr><td>有効期限</td><td>${expiryLabel}</td></tr>
            </table>
          </div>
        </div>
        <div class="mini-preview-parties">
          <div class="mini-preview-to">
            <div class="mini-preview-label">お見積先 / TO</div>
            ${buildToBlock(c, '御中')}
          </div>
          <div class="mini-preview-from">
            <div class="mini-preview-label">発行者 / ISSUED BY</div>
            ${buildFromBlock(s)}
          </div>
        </div>
        <div class="mini-preview-amount-headline">
          <div class="mini-preview-amount-headline-label">お見積金額（税込）</div>
          <div class="mini-preview-amount-headline-value">${fmtYen(totals.total)}</div>
        </div>
        <table class="mini-preview-table">
          <thead><tr>
            <th style="text-align:center">上代</th>
            <th>商品名</th>
            <th style="text-align:center">入数</th>
            <th style="text-align:center">数量</th>
            <th style="text-align:center">単価</th>
            <th style="text-align:center">金額</th>
            <th>JAN</th>
          </tr></thead>
          <tbody>${dataRows}</tbody>
        </table>
        <div class="mini-preview-totals-row">
          <div class="mini-preview-totals-notes">
            <div class="mini-preview-totals-notes-label">備考 / NOTES</div>
            ${data.notes ? esc(data.notes).replace(/\n/g,'<br>') : ''}
          </div>
          <table class="mini-preview-totals-table">
            ${buildTotalsRows(totals, isPersonal, '合計（税込）')}
          </table>
        </div>
      </div>
    `;
  }

  function renderOrderPreview(target, data) {
    injectStyles();
    if (!target) return;
    target.innerHTML = `
      <div class="mini-preview-wrap">
        ${buildDeliveryHTML(data)}
        ${buildInvoiceHTML(data)}
      </div>
    `;
  }

  function renderQuotationMiniPreview(target, data) {
    injectStyles();
    if (!target) return;
    target.innerHTML = `
      <div class="mini-preview-wrap">
        ${buildQuotationHTML(data)}
      </div>
    `;
  }

  global.MeguReePreview = {
    renderOrder: renderOrderPreview,
    renderQuotation: renderQuotationMiniPreview,
    formatZip: formatZip,
    formatJan: formatJan,
  };
})(typeof window !== 'undefined' ? window : globalThis);
