-- Migration 018: Add consent tracking columns to accounts and inquiries
-- Purpose:
--   Persist evidence of user consent to terms.html and privacy.html.
--   Required to satisfy improved Personal Information Protection Law (改正個情法)
--   regarding cross-border transfer (越境移転) consent.
-- Apply in Supabase Dashboard > SQL Editor.

-- 1. Add consent columns to accounts (consent recorded at invite registration time)
ALTER TABLE accounts
  ADD COLUMN IF NOT EXISTS consented_at timestamptz,
  ADD COLUMN IF NOT EXISTS consented_terms_version text,
  ADD COLUMN IF NOT EXISTS consented_privacy_version text;

-- 2. Add consent columns to inquiries (consent recorded at contact form submission)
ALTER TABLE inquiries
  ADD COLUMN IF NOT EXISTS consented_at timestamptz,
  ADD COLUMN IF NOT EXISTS consented_terms_version text,
  ADD COLUMN IF NOT EXISTS consented_privacy_version text;

-- 3. Update register_invited_account RPC to accept and persist consent info
--    Drop old 4-argument signature first so the new signature replaces it cleanly.
DROP FUNCTION IF EXISTS public.register_invited_account(text, text, text, text);

CREATE OR REPLACE FUNCTION public.register_invited_account(
  p_token text,
  p_company_name text,
  p_login_id text,
  p_password text,
  p_terms_version text DEFAULT NULL,
  p_privacy_version text DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_inv invitations%rowtype;
  v_tenant_id uuid;
  v_consented_at timestamptz;
BEGIN
  IF p_token IS NULL OR length(trim(p_token)) = 0 THEN
    RETURN json_build_object('success', false, 'error', 'invalid_token');
  END IF;

  IF p_company_name IS NULL OR length(trim(p_company_name)) = 0 THEN
    RETURN json_build_object('success', false, 'error', 'company_required');
  END IF;

  IF p_login_id IS NULL OR length(trim(p_login_id)) = 0 THEN
    RETURN json_build_object('success', false, 'error', 'login_required');
  END IF;

  IF p_password IS NULL OR length(p_password) < 6 THEN
    RETURN json_build_object('success', false, 'error', 'password_too_short');
  END IF;

  SELECT * INTO v_inv
  FROM invitations
  WHERE token = p_token
    AND used_at IS NULL
    AND expires_at > now()
  LIMIT 1
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'invalid_or_expired');
  END IF;

  v_tenant_id := v_inv.tenant_id;

  IF EXISTS (SELECT 1 FROM accounts WHERE login_id = p_login_id) THEN
    RETURN json_build_object('success', false, 'error', 'login_id_exists');
  END IF;

  -- Record consent timestamp only when at least one version is provided
  IF p_terms_version IS NOT NULL OR p_privacy_version IS NOT NULL THEN
    v_consented_at := now();
  ELSE
    v_consented_at := NULL;
  END IF;

  UPDATE tenants
  SET name = p_company_name
  WHERE id = v_tenant_id;

  INSERT INTO accounts (
    login_id, name, role, password, password_hash, tenant_id,
    consented_at, consented_terms_version, consented_privacy_version
  )
  VALUES (
    p_login_id, p_company_name, 'admin', '', crypt(p_password, gen_salt('bf')), v_tenant_id,
    v_consented_at, p_terms_version, p_privacy_version
  );

  INSERT INTO settings (tenant_id, company_name)
  VALUES (v_tenant_id, p_company_name)
  ON CONFLICT DO NOTHING;

  UPDATE invitations
  SET used_at = now()
  WHERE id = v_inv.id;

  RETURN json_build_object('success', true, 'tenant_id', v_tenant_id);
EXCEPTION
  WHEN unique_violation THEN
    RETURN json_build_object('success', false, 'error', 'login_id_exists');
  WHEN undefined_function THEN
    RETURN json_build_object('success', false, 'error', 'pgcrypto_missing', 'detail', SQLERRM);
  WHEN undefined_column THEN
    RETURN json_build_object('success', false, 'error', 'schema_missing_column', 'detail', SQLERRM);
  WHEN not_null_violation THEN
    RETURN json_build_object('success', false, 'error', 'schema_required_column', 'detail', SQLERRM);
  WHEN check_violation THEN
    RETURN json_build_object('success', false, 'error', 'schema_check_violation', 'detail', SQLERRM);
  WHEN foreign_key_violation THEN
    RETURN json_build_object('success', false, 'error', 'schema_foreign_key', 'detail', SQLERRM);
  WHEN insufficient_privilege THEN
    RETURN json_build_object('success', false, 'error', 'permission_denied', 'detail', SQLERRM);
  WHEN OTHERS THEN
    RETURN json_build_object('success', false, 'error', 'db_error', 'detail', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION public.register_invited_account(text, text, text, text, text, text)
  TO anon, authenticated, service_role;
