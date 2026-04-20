-- Migration: RLS（Row Level Security）有効化
-- 適用方法: Supabase Dashboard > SQL Editor に貼り付けて実行
-- 注意: 実行前に全画面の動作確認を推奨

-- ============================================================
-- ヘルパー関数
-- ============================================================
CREATE OR REPLACE FUNCTION jwt_tenant_id() RETURNS text
  LANGUAGE sql STABLE AS $$
  SELECT auth.jwt()->'user_metadata'->>'tenant_id'
$$;

CREATE OR REPLACE FUNCTION jwt_role() RETURNS text
  LANGUAGE sql STABLE AS $$
  SELECT auth.jwt()->'user_metadata'->>'role'
$$;

-- ============================================================
-- tenants
-- ============================================================
ALTER TABLE tenants ENABLE ROW LEVEL SECURITY;

CREATE POLICY "tenants_super_admin" ON tenants FOR ALL
  USING (jwt_role() = 'super_admin');

CREATE POLICY "tenants_authenticated_select" ON tenants FOR SELECT
  TO authenticated
  USING (id::text = jwt_tenant_id());

-- ============================================================
-- accounts
-- ============================================================
ALTER TABLE accounts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "accounts_super_admin" ON accounts FOR ALL
  USING (jwt_role() = 'super_admin');

CREATE POLICY "accounts_own_read" ON accounts FOR SELECT
  TO authenticated
  USING (login_id = auth.jwt()->'user_metadata'->>'login_id');

CREATE POLICY "accounts_own_update" ON accounts FOR UPDATE
  TO authenticated
  USING (login_id = auth.jwt()->'user_metadata'->>'login_id');

-- invite.html: 招待URLからの新規登録
CREATE POLICY "accounts_anon_insert" ON accounts FOR INSERT
  TO anon WITH CHECK (true);

-- ============================================================
-- customers
-- ============================================================
ALTER TABLE customers ENABLE ROW LEVEL SECURITY;

CREATE POLICY "customers_super_admin" ON customers FOR ALL
  USING (jwt_role() = 'super_admin');

CREATE POLICY "customers_tenant_all" ON customers FOR ALL
  TO authenticated
  USING (tenant_id::text = jwt_tenant_id())
  WITH CHECK (tenant_id::text = jwt_tenant_id());

-- order_form.html: 取引先名・IDの参照
CREATE POLICY "customers_anon_select" ON customers FOR SELECT
  TO anon USING (true);

-- ============================================================
-- products
-- ============================================================
ALTER TABLE products ENABLE ROW LEVEL SECURITY;

CREATE POLICY "products_super_admin" ON products FOR ALL
  USING (jwt_role() = 'super_admin');

CREATE POLICY "products_tenant_all" ON products FOR ALL
  TO authenticated
  USING (tenant_id::text = jwt_tenant_id())
  WITH CHECK (tenant_id::text = jwt_tenant_id());

-- order_form.html: 商品一覧の参照
CREATE POLICY "products_anon_select" ON products FOR SELECT
  TO anon USING (true);

-- ============================================================
-- pricing
-- ============================================================
ALTER TABLE pricing ENABLE ROW LEVEL SECURITY;

CREATE POLICY "pricing_super_admin" ON pricing FOR ALL
  USING (jwt_role() = 'super_admin');

CREATE POLICY "pricing_tenant_all" ON pricing FOR ALL
  TO authenticated
  USING (tenant_id::text = jwt_tenant_id())
  WITH CHECK (tenant_id::text = jwt_tenant_id());

-- order_form.html: 掛け率の参照
CREATE POLICY "pricing_anon_select" ON pricing FOR SELECT
  TO anon USING (true);

-- ============================================================
-- orders
-- ============================================================
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;

CREATE POLICY "orders_super_admin" ON orders FOR ALL
  USING (jwt_role() = 'super_admin');

CREATE POLICY "orders_tenant_all" ON orders FOR ALL
  TO authenticated
  USING (tenant_id::text = jwt_tenant_id())
  WITH CHECK (tenant_id::text = jwt_tenant_id());

-- order_form.html: 注文の新規登録
CREATE POLICY "orders_anon_insert" ON orders FOR INSERT
  TO anon WITH CHECK (true);

-- ============================================================
-- order_items
-- ============================================================
ALTER TABLE order_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY "order_items_super_admin" ON order_items FOR ALL
  USING (jwt_role() = 'super_admin');

CREATE POLICY "order_items_tenant_all" ON order_items FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM orders
      WHERE orders.id = order_items.order_id
        AND orders.tenant_id::text = jwt_tenant_id()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM orders
      WHERE orders.id = order_items.order_id
        AND orders.tenant_id::text = jwt_tenant_id()
    )
  );

-- order_form.html: 明細の新規登録
CREATE POLICY "order_items_anon_insert" ON order_items FOR INSERT
  TO anon WITH CHECK (true);

-- ============================================================
-- invoices
-- ============================================================
ALTER TABLE invoices ENABLE ROW LEVEL SECURITY;

CREATE POLICY "invoices_super_admin" ON invoices FOR ALL
  USING (jwt_role() = 'super_admin');

CREATE POLICY "invoices_tenant_all" ON invoices FOR ALL
  TO authenticated
  USING (tenant_id::text = jwt_tenant_id())
  WITH CHECK (tenant_id::text = jwt_tenant_id());

-- ============================================================
-- settings
-- ============================================================
ALTER TABLE settings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "settings_super_admin" ON settings FOR ALL
  USING (jwt_role() = 'super_admin');

CREATE POLICY "settings_tenant_all" ON settings FOR ALL
  TO authenticated
  USING (tenant_id::text = jwt_tenant_id())
  WITH CHECK (tenant_id::text = jwt_tenant_id());

-- ============================================================
-- inquiries
-- ============================================================
ALTER TABLE inquiries ENABLE ROW LEVEL SECURITY;

CREATE POLICY "inquiries_super_admin" ON inquiries FOR ALL
  USING (jwt_role() = 'super_admin');

-- contact.html: 問い合わせの送信（ログイン不要ページ）
CREATE POLICY "inquiries_anon_insert" ON inquiries FOR INSERT
  TO anon WITH CHECK (true);

-- ============================================================
-- invitations
-- ============================================================
ALTER TABLE invitations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "invitations_super_admin" ON invitations FOR ALL
  USING (jwt_role() = 'super_admin');

CREATE POLICY "invitations_tenant_select" ON invitations FOR SELECT
  TO authenticated
  USING (tenant_id::text = jwt_tenant_id());

-- invite.html: トークンで招待確認（ログイン不要）
CREATE POLICY "invitations_anon_select" ON invitations FOR SELECT
  TO anon USING (used_at IS NULL);

CREATE POLICY "invitations_anon_update" ON invitations FOR UPDATE
  TO anon USING (used_at IS NULL);
