-- Migration: fix settings table for multi-tenant company settings
-- Purpose:
--   The legacy single-tenant schema allowed only one settings row via
--   CHECK (id = 1). In multi-tenant mode each tenant needs exactly one row.
-- Apply in Supabase Dashboard > SQL Editor.

-- 1. Remove the old single-row check constraint.
ALTER TABLE settings
  DROP CONSTRAINT IF EXISTS settings_single_row;

-- 2. Ensure integer/bigint id columns can auto-generate values when older
--    single-row schemas do not already have a default.
DO $$
DECLARE
  v_data_type text;
  v_has_default boolean;
BEGIN
  SELECT data_type, column_default IS NOT NULL
    INTO v_data_type, v_has_default
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND table_name = 'settings'
    AND column_name = 'id';

  IF v_data_type IN ('integer', 'bigint', 'smallint') AND NOT v_has_default THEN
    IF to_regclass('public.settings_id_seq') IS NULL THEN
      EXECUTE 'CREATE SEQUENCE public.settings_id_seq OWNED BY public.settings.id';
    END IF;

    EXECUTE 'SELECT setval(''public.settings_id_seq'', COALESCE((SELECT MAX(id) FROM public.settings), 0) + 1, false)';
    EXECUTE 'ALTER TABLE public.settings ALTER COLUMN id SET DEFAULT nextval(''public.settings_id_seq'')';
  END IF;
END $$;

-- 3. Enforce one settings row per tenant so PostgREST upsert can use
--    on_conflict=tenant_id safely.
CREATE UNIQUE INDEX IF NOT EXISTS settings_tenant_id_unique
  ON settings (tenant_id);
