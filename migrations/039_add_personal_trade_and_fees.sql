-- 039_add_personal_trade_and_fees.sql
-- 個人間取引（メルカリ等）フラグと、受注・見積・請求書の手数料・送料カラムを追加。
--
-- 1) customers.is_personal_trade
--    取引先マスタに「個人間取引」フラグを追加。
--    true = メルカリ等の個人間取引（帳票で税込み単価＋内税表示）
--    false = 既存の卸取引先（帳票で税抜き単価＋外税表示）
--
-- 2) orders / quotations / invoices に is_personal_trade スナップショット
--    取引先のフラグを発行時にコピー保存。後から取引先のフラグを変えても
--    既発行帳票の表示が変わらないように。
--
-- 3) orders / quotations / invoices に handling_fee, shipping_fee
--    手数料・送料の固定入力欄。税抜き金額で保存（正の値）。
--    集計時に控除（マイナス計上）として扱う。税率は標準10%固定。
--
-- 既存行は false / 0 で初期化。既発行帳票・既存帳票への影響なし。
-- インボイス制度上の改変もなし。

BEGIN;

-- 1) 取引先マスタ：個人間取引フラグ
ALTER TABLE customers
  ADD COLUMN IF NOT EXISTS is_personal_trade boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN customers.is_personal_trade IS '個人間取引フラグ（true=メルカリ等の個人取引・帳票で税込み単価＋内税表示、false=既存卸取引先・税抜き単価＋外税表示）';

-- 2) 受注：個人間取引スナップショット＋手数料・送料
ALTER TABLE orders
  ADD COLUMN IF NOT EXISTS is_personal_trade boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS handling_fee numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS shipping_fee numeric NOT NULL DEFAULT 0;

COMMENT ON COLUMN orders.is_personal_trade IS '個人間取引フラグのスナップショット（受注時の customers.is_personal_trade をコピー）';
COMMENT ON COLUMN orders.handling_fee      IS '手数料（税抜き・正の値で保存・集計時にマイナス計上・標準税率10%固定）';
COMMENT ON COLUMN orders.shipping_fee      IS '送料（税抜き・正の値で保存・集計時にマイナス計上・標準税率10%固定）';

-- 3) 見積書：個人間取引スナップショット＋手数料・送料
ALTER TABLE quotations
  ADD COLUMN IF NOT EXISTS is_personal_trade boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS handling_fee numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS shipping_fee numeric NOT NULL DEFAULT 0;

COMMENT ON COLUMN quotations.is_personal_trade IS '個人間取引フラグのスナップショット（発行時の customers.is_personal_trade をコピー）';
COMMENT ON COLUMN quotations.handling_fee      IS '手数料（税抜き・正の値で保存・集計時にマイナス計上・標準税率10%固定）';
COMMENT ON COLUMN quotations.shipping_fee      IS '送料（税抜き・正の値で保存・集計時にマイナス計上・標準税率10%固定）';

-- 4) 請求書：個人間取引スナップショット＋手数料・送料
ALTER TABLE invoices
  ADD COLUMN IF NOT EXISTS is_personal_trade boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS handling_fee numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS shipping_fee numeric NOT NULL DEFAULT 0;

COMMENT ON COLUMN invoices.is_personal_trade IS '個人間取引フラグのスナップショット（発行時の customers.is_personal_trade をコピー）';
COMMENT ON COLUMN invoices.handling_fee      IS '手数料（税抜き・正の値で保存・集計時にマイナス計上・標準税率10%固定）';
COMMENT ON COLUMN invoices.shipping_fee      IS '送料（税抜き・正の値で保存・集計時にマイナス計上・標準税率10%固定）';

COMMIT;
