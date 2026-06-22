-- 052_add_customer_default_fees.sql
-- 取引先マスタ（customers）に「いつもの手数料・送料」（既定値）を追加。
--
-- 背景：
--   手数料・送料は orders / quotations / invoices には既にあり（migration 039/050/051）、
--   管理画面の新規納品書入力・受注編集では手で入力できる。
--   しかし注文フォーム（shop.html → create_my_order RPC）から来た注文には
--   一切セットされず 0 のままになる。
--   そこで Bカート等の BtoB 受発注の標準（卸が取引先ごとに送料を設定し注文時に自動加算）
--   に倣い、取引先ごとに「いつもの手数料・送料」を持たせ、フォーム注文時に自動コピーする。
--
-- 設計（orders 側の手数料・送料カラムと1:1で対応・解釈もすべて同じ）：
--   default_handling_fee        … 手数料（1単位あたり・税込・正の値）   ← orders.handling_fee
--   default_shipping_fee        … 送料（1単位あたり・税込・正の値）     ← orders.shipping_fee
--   default_handling_fee_charge … 手数料の向き false=差し引き/true=加算  ← orders.handling_fee_charge
--   default_shipping_fee_charge … 送料の向き  false=差し引き/true=加算   ← orders.shipping_fee_charge
--   default_handling_fee_qty    … 手数料の数量（既定1）                 ← orders.handling_fee_qty
--   default_shipping_fee_qty    … 送料の数量（既定1）                   ← orders.shipping_fee_qty
--
-- 既存行は 0 / false / 1 で初期化されるため、既存取引先・既発行帳票・既存注文への影響なし。
-- これは「既定値（テンプレート）」であり、受注に自動コピーされた後は受注側で上書き可能。
-- 既発行の納品書・請求書スナップショットは一切改変しない（インボイス制度）。

BEGIN;

ALTER TABLE customers
  ADD COLUMN IF NOT EXISTS default_handling_fee        numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS default_shipping_fee        numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS default_handling_fee_charge boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS default_shipping_fee_charge boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS default_handling_fee_qty    numeric NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS default_shipping_fee_qty    numeric NOT NULL DEFAULT 1;

COMMENT ON COLUMN customers.default_handling_fee        IS 'いつもの手数料（1単位あたり・税込・正の値）。フォーム注文時に orders.handling_fee へ自動コピー';
COMMENT ON COLUMN customers.default_shipping_fee        IS 'いつもの送料（1単位あたり・税込・正の値）。フォーム注文時に orders.shipping_fee へ自動コピー';
COMMENT ON COLUMN customers.default_handling_fee_charge IS 'いつもの手数料の向き（false=差し引き・既定、true=請求に加算）';
COMMENT ON COLUMN customers.default_shipping_fee_charge IS 'いつもの送料の向き（false=差し引き・既定、true=請求に加算）';
COMMENT ON COLUMN customers.default_handling_fee_qty    IS 'いつもの手数料の数量（既定1）';
COMMENT ON COLUMN customers.default_shipping_fee_qty    IS 'いつもの送料の数量（既定1）';

COMMIT;
