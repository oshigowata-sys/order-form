-- Migration: harden invitation registration and super-admin auth
-- Apply in Supabase Dashboard > SQL Editor.
--
-- Goals:
-- - Stop anon users from broadly selecting/updating invitations.
-- - Stop anon users from inserting arbitrary accounts.
-- - Allow invite registration only through SECURITY DEFINER RPCs that validate tokens.
-- - Ensure account login IDs and invitation tokens cannot be duplicated.

CREATE UNIQUE INDEX IF NOT EXISTS accounts_login_id_unique
  ON accounts (login_id);

CREATE UNIQUE INDEX IF NOT EXISTS invitations_token_unique
  ON invitations (token);

-- Preview only the invitation matching a valid, unused, unexpired token.
CREATE OR REPLACE FUNCTION public.get_invitation_by_token(
  p_token text
)
RETURNS TABLE(tenant_id uuid, email text, expires_at timestamptz)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT i.tenant_id, i.email, i.expires_at
  FROM invitations i
  WHERE i.token = p_token
    AND i.used_at IS NULL
    AND i.expires_at > now()
  LIMIT 1;
END;
$$;

-- Register an account from an invitation token in one transaction.
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

-- Sync super_admin accounts into auth.users for super-login.html.
CREATE OR REPLACE FUNCTION public.sync_auth_super_admin_on_login(
  p_login_id text,
  p_password text
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_account accounts%rowtype;
  v_email text;
  v_hash text;
  v_uid uuid;
BEGIN
  SELECT * INTO v_account
  FROM accounts
  WHERE login_id = p_login_id
    AND crypt(p_password, password_hash) = password_hash
    AND role = 'super_admin'
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  v_email := p_login_id || '@meguree.internal';
  v_hash := crypt(p_password, gen_salt('bf', 10));

  UPDATE auth.users
  SET
    encrypted_password = v_hash,
    email_confirmed_at = COALESCE(email_confirmed_at, now()),
    confirmation_token = COALESCE(confirmation_token, ''),
    recovery_token = COALESCE(recovery_token, ''),
    email_change_token_new = COALESCE(email_change_token_new, ''),
    email_change = COALESCE(email_change, ''),
    raw_user_meta_data = jsonb_build_object(
      'login_id', v_account.login_id,
      'name', v_account.name,
      'role', v_account.role,
      'tenant_id', v_account.tenant_id
    ),
    updated_at = now()
  WHERE email = v_email
  RETURNING id INTO v_uid;

  IF v_uid IS NULL THEN
    v_uid := gen_random_uuid();

    INSERT INTO auth.users (
      id, instance_id, aud, role, email,
      encrypted_password, email_confirmed_at,
      confirmation_token, recovery_token,
      email_change_token_new, email_change,
      raw_app_meta_data, raw_user_meta_data,
      created_at, updated_at, is_sso_user, is_anonymous
    ) VALUES (
      v_uid,
      '00000000-0000-0000-0000-000000000000',
      'authenticated', 'authenticated',
      v_email,
      v_hash,
      now(),
      '', '', '', '',
      '{"provider":"email","providers":["email"]}',
      jsonb_build_object(
        'login_id', v_account.login_id,
        'name', v_account.name,
        'role', v_account.role,
        'tenant_id', v_account.tenant_id
      ),
      now(), now(), false, false
    );

    INSERT INTO auth.identities (
      id, user_id, identity_data, provider,
      last_sign_in_at, created_at, updated_at, provider_id
    ) VALUES (
      gen_random_uuid(), v_uid,
      jsonb_build_object('sub', v_uid::text, 'email', v_email),
      'email',
      now(), now(), now(), v_email
    );
  END IF;

  RETURN v_email;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_invitation_by_token(text) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.register_invited_account(text, text, text, text) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.sync_auth_super_admin_on_login(text, text) TO anon, authenticated, service_role;

DROP POLICY IF EXISTS "accounts_anon_insert" ON accounts;
DROP POLICY IF EXISTS "invitations_anon_select" ON invitations;
DROP POLICY IF EXISTS "invitations_anon_update" ON invitations;
