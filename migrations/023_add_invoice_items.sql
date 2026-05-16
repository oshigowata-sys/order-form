-- Migration: Add invoice_items (snapshot of invoice line items)
-- Apply in Supabase Dashboard > SQL Editor.
--
-- 請求書発行時点の明細スナップショットを保存するテーブル。
-- 既存の invoice.html は期間内の orders + order_items を毎回再集計しており、
-- 商品マスタ(products)を編集すると過去の請求書PDFまで書き換わるリスクがあった。
-- 発行時に invoice_items に明細をコピー保存し、PDF表示時はこちらを優先取得する。
-- 既発行分は invoice_items が空 → 従来通り orders 再集計でフォールバック。
--
-- 設計は quotation_items（migration 019）と同パターン。
-- 明細自体には tenant_id を持たせず、親 invoices.tenant_id 経由で RLS チェック。

CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

CREATE TABLE IF NOT EXISTS invoice_items (
  id uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
  invoice_id uuid NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
  product_id uuid NULL REFERENCES products(id) ON DELETE SET NULL,
  product_code text NOT NULL DEFAULT '',
  product_name text NOT NULL,
  quantity numeric NOT NULL DEFAULT 0,
  unit_price integer NOT NULL DEFAULT 0,
  subtotal integer NOT NULL DEFAULT 0,
  is_food boolean NOT NULL DEFAULT false,
  display_order integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS invoice_items_invoice_order_idx
  ON invoice_items (invoice_id, display_order);

ALTER TABLE invoice_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "invoice_items_super_admin" ON invoice_items;
DROP POLICY IF EXISTS "invoice_items_tenant_all" ON invoice_items;

CREATE POLICY "invoice_items_super_admin" ON invoice_items FOR ALL
  USING (jwt_role() = 'super_admin')
  WITH CHECK (jwt_role() = 'super_admin');

-- 明細の RLS は親 invoices の tenant_id 経由でチェック（quotation_items と同パターン）
CREATE POLICY "invoice_items_tenant_all" ON invoice_items FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM invoices i
      WHERE i.id = invoice_items.invoice_id
        AND i.tenant_id::text = jwt_tenant_id()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM invoices i
      WHERE i.id = invoice_items.invoice_id
        AND i.tenant_id::text = jwt_tenant_id()
    )
  );

COMMENT ON TABLE invoice_items IS '請求書明細スナップショット（発行時点の商品名・単価・税率を固定保存）';
COMMENT ON COLUMN invoice_items.product_code IS '商品コード（発行時点の products.product_code スナップショット）';
COMMENT ON COLUMN invoice_items.product_name IS '商品名（発行時点の products.product_name スナップショット）';
COMMENT ON COLUMN invoice_items.unit_price   IS '販売単価（掛け率反映後・order_items.unit_price のコピー）';
COMMENT ON COLUMN invoice_items.is_food      IS '税率判定用（発行時点の products.is_food スナップショット）';
