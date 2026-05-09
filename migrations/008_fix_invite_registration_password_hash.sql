-- Migration: ensure invite registration can create bcrypt-backed accounts
-- Apply in Supabase Dashboard > SQL Editor.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

ALTER TABLE accounts
  ADD COLUMN IF NOT EXISTS password_hash text;

CREATE OR REPLACE FUNCTION public.register_invited_account(
  p_token text,
  p_company_name text,
  p_login_id text,
  p_password text
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_inv invitations%rowtype;
  v_tenant_id uuid;
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

  UPDATE tenants
  SET name = p_company_name
  WHERE id = v_tenant_id;

  INSERT INTO accounts (login_id, name, role, password, password_hash, tenant_id)
  VALUES (p_login_id, p_company_name, 'admin', '', crypt(p_password, gen_salt('bf', 10)), v_tenant_id);

  INSERT INTO settings (tenant_id, company_name)
  VALUES (v_tenant_id, p_company_name)
  ON CONFLICT DO NOTHING;

  UPDATE invitations
  SET used_at = now()
  WHERE id = v_inv.id;

  RETURN json_build_object('success', true, 'tenant_id', v_tenant_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.register_invited_account(text, text, text, text) TO anon, authenticated, service_role;
