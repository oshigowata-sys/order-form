-- Migration: allow each tenant to register multiple bank accounts
-- Apply in Supabase Dashboard > SQL Editor.

CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

CREATE TABLE IF NOT EXISTS tenant_bank_accounts (
  id uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  bank_name text NOT NULL DEFAULT '',
  bank_branch text NOT NULL DEFAULT '',
  bank_type text NOT NULL DEFAULT '',
  bank_number text NOT NULL DEFAULT '',
  bank_holder text NOT NULL DEFAULT '',
  bank_note text NOT NULL DEFAULT '',
  display_order integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE tenant_bank_accounts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "tenant_bank_accounts_super_admin" ON tenant_bank_accounts;
DROP POLICY IF EXISTS "tenant_bank_accounts_tenant_all" ON tenant_bank_accounts;

CREATE POLICY "tenant_bank_accounts_super_admin" ON tenant_bank_accounts FOR ALL
  USING (jwt_role() = 'super_admin')
  WITH CHECK (jwt_role() = 'super_admin');

CREATE POLICY "tenant_bank_accounts_tenant_all" ON tenant_bank_accounts FOR ALL
  TO authenticated
  USING (tenant_id::text = jwt_tenant_id())
  WITH CHECK (tenant_id::text = jwt_tenant_id());

CREATE INDEX IF NOT EXISTS tenant_bank_accounts_tenant_order_idx
  ON tenant_bank_accounts (tenant_id, display_order, created_at);
