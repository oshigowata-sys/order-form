/**
 * MeguRee 消費税率ヘルパー（共通）
 *
 * 消費税率が改定されたとき、コードを直さず設定画面から切り替えられるようにするための共通処理。
 * 「切替日方式」＝受注日（帳票の対象日）がその日以降なら新税率、それより前の受注は当時の税率のまま。
 * 何も登録されていなければ既定（標準10% / 軽減8%＝食品）で動く＝導入前と完全に同じ挙動。
 *
 * データの出どころ：settings.tax_rate_changes（migration 061・jsonb）
 *   [{"from":"2027-04-01","standard":12,"reduced":10}, ...]
 *
 * 使い方：
 *   1) 画面の初期化で settings 行を渡す（読めなければ渡さなくてよい＝既定で動く）
 *        MeguReeTax.loadFrom(settingsRow);
 *   2) 税率が要る場所で受注日を渡す
 *        MeguReeTax.rate(orderDate, isFood)      -> 0.10 / 0.08 （掛け算用の小数）
 *        MeguReeTax.percent(orderDate, isFood)   -> 10 / 8      （表示用の数値）
 *        MeguReeTax.label(orderDate, isFood)     -> '10%' / '8%'（表示用の文字列）
 *        MeguReeTax.tax(amount, orderDate, isFood) -> Math.round(amount * rate)
 *
 * 日付は 'YYYY-MM-DD' 文字列 / Date / 未指定（＝今日）のいずれでも渡せる。
 * 比較は文字列同士で行う（YYYY-MM-DD は辞書順＝日付順）。Date同士の比較を避け、
 * 過去に請求書発行日で起きた時差ずれ（PR #379）と同種の事故を作らないため。
 */
(function(global) {
  'use strict';

  // 現行の税率。settings に変更予定が無い期間はこれを使う。
  var DEFAULT = { standard: 10, reduced: 8 };

  // 適用開始日の昇順で保持する [{from:'YYYY-MM-DD', standard:Number, reduced:Number}]
  var changes = [];

  function pad2(n) { return (n < 10 ? '0' : '') + n; }

  /** Date / 文字列 / 未指定 を 'YYYY-MM-DD' に正規化する。不正なら今日の日付。 */
  function toYmd(d) {
    if (d instanceof Date && !isNaN(d)) {
      return d.getFullYear() + '-' + pad2(d.getMonth() + 1) + '-' + pad2(d.getDate());
    }
    if (typeof d === 'string' && /^\d{4}-\d{2}-\d{2}/.test(d)) return d.slice(0, 10);
    var now = new Date();
    return now.getFullYear() + '-' + pad2(now.getMonth() + 1) + '-' + pad2(now.getDate());
  }

  function toNum(v, fallback) {
    var n = Number(v);
    return (isFinite(n) && n >= 0) ? n : fallback;
  }

  /**
   * 変更予定をセットする。配列以外・壊れた行は捨てる（設定が壊れていても既定で動き続ける）。
   * @param {Array} arr [{from, standard, reduced}]
   */
  function setChanges(arr) {
    var list = [];
    if (Array.isArray(arr)) {
      for (var i = 0; i < arr.length; i++) {
        var r = arr[i];
        if (!r || typeof r !== 'object') continue;
        var from = (typeof r.from === 'string' && /^\d{4}-\d{2}-\d{2}/.test(r.from)) ? r.from.slice(0, 10) : null;
        if (!from) continue;
        list.push({
          from: from,
          standard: toNum(r.standard, DEFAULT.standard),
          reduced:  toNum(r.reduced,  DEFAULT.reduced)
        });
      }
    }
    list.sort(function(a, b) { return a.from < b.from ? -1 : a.from > b.from ? 1 : 0; });
    changes = list;
  }

  /** settings の1行（select=* の結果）から取り込む。行が無くても安全。 */
  function loadFrom(settingsRow) {
    var raw = settingsRow && settingsRow.tax_rate_changes;
    if (typeof raw === 'string') {
      try { raw = JSON.parse(raw); } catch (e) { raw = []; }
    }
    setChanges(raw);
  }

  /** 現在セットされている変更予定（設定画面の編集用）。 */
  function getChanges() {
    return changes.map(function(r) { return { from: r.from, standard: r.standard, reduced: r.reduced }; });
  }

  /**
   * その日に適用される税率を返す。
   * @returns {{standard:number, reduced:number}} %の数値
   */
  function forDate(date) {
    var ymd = toYmd(date);
    var cur = DEFAULT;
    for (var i = 0; i < changes.length; i++) {
      if (changes[i].from <= ymd) cur = changes[i]; else break;
    }
    return { standard: cur.standard, reduced: cur.reduced };
  }

  /** %の数値（10 / 8）。表示用。 */
  function percent(date, isFood) {
    var r = forDate(date);
    return isFood ? r.reduced : r.standard;
  }

  /** 掛け算用の小数（0.10 / 0.08）。 */
  function rate(date, isFood) {
    return percent(date, isFood) / 100;
  }

  /** 表示用の文字列（'10%' / '8%'）。 */
  function label(date, isFood) {
    return percent(date, isFood) + '%';
  }

  /** 税額（円・四捨五入）。既存実装と同じ Math.round。 */
  function tax(amount, date, isFood) {
    return Math.round(Number(amount || 0) * rate(date, isFood));
  }

  /** 税込に変換（税抜→税込）。 */
  function toIncl(amount, date, isFood) {
    return Number(amount || 0) + tax(amount, date, isFood);
  }

  /** 税込→税抜（円未満は四捨五入。商品マスタの税込入力で使用＝従来と同じ丸め）。 */
  function toExcl(inclAmount, date, isFood) {
    return Math.round(Number(inclAmount || 0) / (1 + rate(date, isFood)));
  }

  /** その日に軽減税率（標準と違う率）が存在するか。表示の出し分け用。 */
  function hasReduced(date) {
    var r = forDate(date);
    return r.reduced !== r.standard;
  }

  global.MeguReeTax = {
    DEFAULT: DEFAULT,
    setChanges: setChanges,
    loadFrom: loadFrom,
    getChanges: getChanges,
    forDate: forDate,
    percent: percent,
    rate: rate,
    label: label,
    tax: tax,
    toIncl: toIncl,
    toExcl: toExcl,
    hasReduced: hasReduced
  };
})(window);
