-- Migration: fix settings table for multi-tenant company settings
-- Purpose:
--   Legacy single-tenant schema had CHECK (id = 1) + DEFAULT 1, so only the
--   first tenant could ever own the settings row. Every other tenant's
--   "settings" save POST hit HTTP 409 (CHECK violation), making the company
--   info / bank info form silently unusable for them.
-- Fix:
--   Drop the single-row CHECK, drop the hard-coded "DEFAULT 1", attach a
--   sequence so each tenant can insert its own row with a fresh id, and
--   enforce one row per tenant.
-- Apply in Supabase Dashboard > SQL Editor (or via MCP apply_migration).

-- 1. Remove the legacy single-row check constraint.
ALTER TABLE settings
  DROP CONSTRAINT IF EXISTS settings_single_row;

-- 2. Drop the legacy hard-coded "DEFAULT 1" so new inserts can use a sequence.
ALTER TABLE settings ALTER COLUMN id DROP DEFAULT;

-- 3. Create / reuse a sequence and seed it past existing max(id).
CREATE SEQUENCE IF NOT EXISTS public.settings_id_seq OWNED BY public.settings.id;
SELECT setval(
  'public.settings_id_seq',
  COALESCE((SELECT MAX(id) FROM public.settings), 0) + 1,
  false
);

-- 4. Use the sequence as the new default for id.
ALTER TABLE settings
  ALTER COLUMN id SET DEFAULT nextval('public.settings_id_seq');

-- 5. Enforce one settings row per tenant so PATCH-then-INSERT stays safe.
CREATE UNIQUE INDEX IF NOT EXISTS settings_tenant_id_unique
  ON settings (tenant_id);
