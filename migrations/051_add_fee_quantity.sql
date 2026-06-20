-- 051_add_fee_quantity.sql
-- 手数料・送料に「数量」を追加。1箱あたりの手数料・送料 × 箱数 で計算できるようにする。
--
-- 背景：1ケース（箱）ごとに手数料・送料がかかる運用がある（例：10箱なら送料×10）。
--   これまで handling_fee / shipping_fee は「合計の税込金額」だったが、
--   数量導入後は「1単位（1箱）あたりの税込金額」と解釈し、実際の合計 = 金額 × 数量 とする。
--
-- 設計：
--   handling_fee_qty / shipping_fee_qty（既定 1）。実効の手数料・送料 = fee × qty。
--   既存行は qty=1 で初期化されるため fee × 1 = 従来どおりの金額となり、過去データ・既発行帳票は不変。
--   インボイス制度上の遡及改変なし。
--
-- 対象テーブル：orders（受注）／quotations（見積書）／invoices（請求書スナップショット）

BEGIN;

ALTER TABLE orders
  ADD COLUMN IF NOT EXISTS handling_fee_qty numeric NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS shipping_fee_qty numeric NOT NULL DEFAULT 1;

COMMENT ON COLUMN orders.handling_fee_qty IS '手数料の数量（既定1）。実効手数料 = handling_fee（1単位あたり税込）× handling_fee_qty';
COMMENT ON COLUMN orders.shipping_fee_qty IS '送料の数量（既定1）。実効送料 = shipping_fee（1単位あたり税込）× shipping_fee_qty';

ALTER TABLE quotations
  ADD COLUMN IF NOT EXISTS handling_fee_qty numeric NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS shipping_fee_qty numeric NOT NULL DEFAULT 1;

COMMENT ON COLUMN quotations.handling_fee_qty IS '手数料の数量（既定1）。実効手数料 = handling_fee × handling_fee_qty';
COMMENT ON COLUMN quotations.shipping_fee_qty IS '送料の数量（既定1）。実効送料 = shipping_fee × shipping_fee_qty';

ALTER TABLE invoices
  ADD COLUMN IF NOT EXISTS handling_fee_qty numeric NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS shipping_fee_qty numeric NOT NULL DEFAULT 1;

COMMENT ON COLUMN invoices.handling_fee_qty IS '手数料の数量（既定1）。期間請求書は正味金額×数量1で記録';
COMMENT ON COLUMN invoices.shipping_fee_qty IS '送料の数量（既定1）。期間請求書は正味金額×数量1で記録';

COMMIT;
