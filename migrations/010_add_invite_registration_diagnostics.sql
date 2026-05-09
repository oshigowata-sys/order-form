-- Migration: add no-write diagnostics for invite registration
-- Apply in Supabase Dashboard > SQL Editor.

CREATE OR REPLACE FUNCTION public.diagnose_invited_account_registration(
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
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'invalid_or_expired');
  END IF;

  v_tenant_id := v_inv.tenant_id;

  IF EXISTS (SELECT 1 FROM accounts WHERE login_id = p_login_id) THEN
    RETURN json_build_object('success', false, 'error', 'login_id_exists');
  END IF;

  BEGIN
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

    RAISE EXCEPTION 'diagnostic_rollback';
  EXCEPTION
    WHEN raise_exception THEN
      IF SQLERRM = 'diagnostic_rollback' THEN
        RETURN json_build_object('success', true, 'diagnostic', 'registration_would_succeed', 'tenant_id', v_tenant_id);
      END IF;
      RETURN json_build_object('success', false, 'error', 'db_error', 'detail', SQLERRM);
    WHEN unique_violation THEN
      RETURN json_build_object('success', false, 'error', 'login_id_exists', 'detail', SQLERRM);
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
END;
$$;

GRANT EXECUTE ON FUNCTION public.diagnose_invited_account_registration(text, text, text, text) TO anon, authenticated, service_role;
