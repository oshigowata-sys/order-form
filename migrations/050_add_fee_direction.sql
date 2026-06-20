-- 050_add_fee_direction.sql
-- 手数料・送料の「向き」（請求に加算する／合計から差し引く）を保存する列を追加。
--
-- 背景：
--   migration 039 で handling_fee / shipping_fee を「正の値で保存・集計時にマイナス計上（控除）」
--   として導入した。しかし小売店・個人売りでは送料を「請求に上乗せ（プラス計上）」したいケースがある。
--   そこで金額（正の値）はそのままに、向きだけを別フラグで持たせる。
--
-- 設計：
--   *_fee_charge = false → 差し引き（控除・現行どおり・既定）
--   *_fee_charge = true  → 請求に加算（プラス）
--   金額そのもの（handling_fee / shipping_fee）は引き続き「正の値（マグニチュード）」で保存。
--   既存行・既発行帳票は false（＝従来どおり差し引き）で初期化されるため、過去の金額は一切変わらない。
--   インボイス制度上の遡及改変なし。
--
-- 対象テーブル：orders（受注）／quotations（見積書）／invoices（請求書スナップショット）
--   ※ invoices は期間まとめ請求書のスナップショット。複数受注の向きが混在する場合は
--     発行時に「符号付きの正味」を計算し、handling_fee/shipping_fee に正味の絶対値、
--     *_fee_charge に正味の符号（正なら true）を記録する運用とする（表示は1行の正味のみ）。

BEGIN;

-- 受注
ALTER TABLE orders
  ADD COLUMN IF NOT EXISTS handling_fee_charge boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS shipping_fee_charge boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN orders.handling_fee_charge IS '手数料の向き（false=差し引き/控除・既定、true=請求に加算）。金額は handling_fee に正の値で保存';
COMMENT ON COLUMN orders.shipping_fee_charge IS '送料の向き（false=差し引き/控除・既定、true=請求に加算）。金額は shipping_fee に正の値で保存';

-- 見積書
ALTER TABLE quotations
  ADD COLUMN IF NOT EXISTS handling_fee_charge boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS shipping_fee_charge boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN quotations.handling_fee_charge IS '手数料の向き（false=差し引き/控除・既定、true=請求に加算）';
COMMENT ON COLUMN quotations.shipping_fee_charge IS '送料の向き（false=差し引き/控除・既定、true=請求に加算）';

-- 請求書（スナップショット）
ALTER TABLE invoices
  ADD COLUMN IF NOT EXISTS handling_fee_charge boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS shipping_fee_charge boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN invoices.handling_fee_charge IS '手数料の向き（false=差し引き/控除・既定、true=請求に加算）。期間請求書は発行時に正味の符号を記録';
COMMENT ON COLUMN invoices.shipping_fee_charge IS '送料の向き（false=差し引き/控除・既定、true=請求に加算）。期間請求書は発行時に正味の符号を記録';

COMMIT;
