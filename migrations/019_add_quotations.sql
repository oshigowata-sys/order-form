-- Migration: Add quotations (see "見積書") and quotation_items tables
-- Apply in Supabase Dashboard > SQL Editor.

CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

-- ================================================================
-- 1. quotations (header)
-- ================================================================
CREATE TABLE IF NOT EXISTS quotations (
  id uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  quotation_number text NOT NULL,
  customer_id uuid NULL REFERENCES customers(id) ON DELETE SET NULL,
  customer_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
  issued_date date NOT NULL DEFAULT CURRENT_DATE,
  expiry_date date NOT NULL,
  subtotal numeric NOT NULL DEFAULT 0,
  tax_amount numeric NOT NULL DEFAULT 0,
  total_incl_tax numeric NOT NULL DEFAULT 0,
  notes text NOT NULL DEFAULT '',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT quotations_tenant_number_unique UNIQUE (tenant_id, quotation_number)
);

CREATE INDEX IF NOT EXISTS quotations_tenant_issued_idx
  ON quotations (tenant_id, issued_date DESC);

CREATE INDEX IF NOT EXISTS quotations_tenant_customer_idx
  ON quotations (tenant_id, customer_id);

ALTER TABLE quotations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "quotations_super_admin" ON quotations;
DROP POLICY IF EXISTS "quotations_tenant_all" ON quotations;

CREATE POLICY "quotations_super_admin" ON quotations FOR ALL
  USING (jwt_role() = 'super_admin')
  WITH CHECK (jwt_role() = 'super_admin');

CREATE POLICY "quotations_tenant_all" ON quotations FOR ALL
  TO authenticated
  USING (tenant_id::text = jwt_tenant_id())
  WITH CHECK (tenant_id::text = jwt_tenant_id());

-- updated_at auto-update trigger
CREATE OR REPLACE FUNCTION set_quotations_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS quotations_set_updated_at ON quotations;
CREATE TRIGGER quotations_set_updated_at
  BEFORE UPDATE ON quotations
  FOR EACH ROW
  EXECUTE FUNCTION set_quotations_updated_at();

-- ================================================================
-- 2. quotation_items (detail lines)
-- ================================================================
CREATE TABLE IF NOT EXISTS quotation_items (
  id uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
  quotation_id uuid NOT NULL REFERENCES quotations(id) ON DELETE CASCADE,
  product_id uuid NULL REFERENCES products(id) ON DELETE SET NULL,
  product_code text NOT NULL DEFAULT '',
  product_name text NOT NULL,
  quantity numeric NOT NULL DEFAULT 0,
  unit_price numeric NOT NULL DEFAULT 0,
  subtotal numeric NOT NULL DEFAULT 0,
  is_food boolean NOT NULL DEFAULT false,
  display_order integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS quotation_items_quotation_order_idx
  ON quotation_items (quotation_id, display_order);

ALTER TABLE quotation_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "quotation_items_super_admin" ON quotation_items;
DROP POLICY IF EXISTS "quotation_items_tenant_all" ON quotation_items;

CREATE POLICY "quotation_items_super_admin" ON quotation_items FOR ALL
  USING (jwt_role() = 'super_admin')
  WITH CHECK (jwt_role() = 'super_admin');

-- 明細の RLS は親 quotations の tenant_id 経由でチェック
CREATE POLICY "quotation_items_tenant_all" ON quotation_items FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM quotations q
      WHERE q.id = quotation_items.quotation_id
        AND q.tenant_id::text = jwt_tenant_id()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM quotations q
      WHERE q.id = quotation_items.quotation_id
        AND q.tenant_id::text = jwt_tenant_id()
    )
  );

-- ================================================================
-- 3. 見積番号採番関数
-- ================================================================
-- テナント単位で年ごとの連番（Q-2026-001, Q-2026-002, ...）
-- 同じテナント内で同年に発行された見積書の連番が一意になる
CREATE OR REPLACE FUNCTION generate_quotation_number(p_tenant_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_year text;
  v_seq integer;
BEGIN
  -- 日本時間ベースで年を決定
  v_year := to_char(now() AT TIME ZONE 'Asia/Tokyo', 'YYYY');

  SELECT COALESCE(MAX(CAST(SUBSTRING(quotation_number FROM ('^Q-' || v_year || '-(\d+)$')) AS integer)), 0) + 1
  INTO v_seq
  FROM quotations
  WHERE tenant_id = p_tenant_id
    AND quotation_number ~ ('^Q-' || v_year || '-\d+$');

  RETURN 'Q-' || v_year || '-' || lpad(v_seq::text, 3, '0');
END;
$$;

GRANT EXECUTE ON FUNCTION generate_quotation_number(uuid) TO authenticated;
