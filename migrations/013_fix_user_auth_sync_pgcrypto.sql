-- Migration: fix normal user Auth sync after pgcrypto moved to the extensions schema
-- Apply in Supabase Dashboard > SQL Editor.

CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

DROP FUNCTION IF EXISTS public.verify_login(text, text);

CREATE OR REPLACE FUNCTION public.verify_login(
  p_login_id text,
  p_password text
)
RETURNS TABLE(login_id text, name text, role text, tenant_id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_row accounts%rowtype;
  v_valid boolean := false;
BEGIN
  SELECT * INTO v_row FROM accounts WHERE accounts.login_id = p_login_id;
  IF NOT FOUND THEN RETURN; END IF;

  IF v_row.password_hash IS NOT NULL AND v_row.password_hash <> '' THEN
    v_valid := (v_row.password_hash = crypt(p_password, v_row.password_hash));
  ELSIF v_row.password = encode(digest(p_password, 'sha256'), 'hex') THEN
    v_valid := true;
    UPDATE accounts SET password_hash = crypt(p_password, gen_salt('bf')), password = ''
    WHERE accounts.login_id = p_login_id;
  ELSIF v_row.password = p_password THEN
    v_valid := true;
    UPDATE accounts SET password_hash = crypt(p_password, gen_salt('bf')), password = ''
    WHERE accounts.login_id = p_login_id;
  END IF;

  IF v_valid THEN
    RETURN QUERY SELECT v_row.login_id, v_row.name, v_row.role, v_row.tenant_id;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.change_password(
  p_login_id text,
  p_current_password text,
  p_new_password text
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_row accounts%rowtype;
  v_valid boolean := false;
BEGIN
  SELECT * INTO v_row FROM accounts WHERE accounts.login_id = p_login_id;
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'not_found');
  END IF;

  IF v_row.password_hash IS NOT NULL AND v_row.password_hash <> '' THEN
    v_valid := (v_row.password_hash = crypt(p_current_password, v_row.password_hash));
  ELSIF v_row.password = encode(digest(p_current_password, 'sha256'), 'hex') THEN
    v_valid := true;
  ELSIF v_row.password = p_current_password THEN
    v_valid := true;
  END IF;

  IF NOT v_valid THEN
    RETURN json_build_object('success', false, 'error', 'invalid_password');
  END IF;

  UPDATE accounts
  SET password_hash = crypt(p_new_password, gen_salt('bf')),
      password = ''
  WHERE accounts.login_id = p_login_id;

  RETURN json_build_object('success', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_auth_user_on_login(
  p_login_id text,
  p_password text
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, extensions
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
    AND role != 'super_admin'
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  v_email := CASE
    WHEN p_login_id LIKE '%@%' THEN p_login_id
    ELSE p_login_id || '@meguree.internal'
  END;

  v_hash := crypt(p_password, gen_salt('bf'));

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

GRANT EXECUTE ON FUNCTION public.verify_login(text, text) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.change_password(text, text, text) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.sync_auth_user_on_login(text, text) TO anon, authenticated, service_role;
