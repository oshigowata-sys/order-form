-- 016_fix_auth_app_metadata.sql
-- Fix: sync_auth_user_on_login was writing tenant_id/role to raw_user_meta_data
-- but RLS reads from app_metadata (raw_app_meta_data). Result: every JWT issued
-- through this RPC had no tenant_id claim, so all tenant-scoped writes failed
-- with WITH CHECK violations.
--
-- This migration:
--   1) Rewrites the function so both INSERT and UPDATE branches populate
--      raw_app_meta_data with login_id/name/role/tenant_id.
--   2) Backfills raw_app_meta_data for any existing auth.users row that is
--      linked to a public.accounts row but missing tenant_id in app_metadata.

CREATE OR REPLACE FUNCTION public.sync_auth_user_on_login(p_login_id text, p_password text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'extensions'
AS $function$
  DECLARE
    v_account accounts%rowtype;
    v_email text;
    v_hash text;
    v_uid uuid;
    v_app_meta jsonb;
    v_user_meta jsonb;
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

    v_app_meta := jsonb_build_object(
      'provider', 'email',
      'providers', jsonb_build_array('email'),
      'login_id', v_account.login_id,
      'name', v_account.name,
      'role', v_account.role,
      'tenant_id', v_account.tenant_id
    );

    v_user_meta := jsonb_build_object(
      'login_id', v_account.login_id,
      'name', v_account.name,
      'role', v_account.role,
      'tenant_id', v_account.tenant_id
    );

    UPDATE auth.users
    SET
      encrypted_password = v_hash,
      email_confirmed_at = COALESCE(email_confirmed_at, now()),
      confirmation_token = COALESCE(confirmation_token, ''),
      recovery_token = COALESCE(recovery_token, ''),
      email_change_token_new = COALESCE(email_change_token_new, ''),
      email_change = COALESCE(email_change, ''),
      raw_app_meta_data = v_app_meta,
      raw_user_meta_data = v_user_meta,
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
        v_app_meta,
        v_user_meta,
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
  $function$;

-- Backfill: any auth.users row whose email matches a non-super_admin account
-- but is missing tenant_id in raw_app_meta_data gets repaired.
UPDATE auth.users u
SET raw_app_meta_data = jsonb_build_object(
      'provider', 'email',
      'providers', jsonb_build_array('email'),
      'login_id', a.login_id,
      'name', a.name,
      'role', a.role,
      'tenant_id', a.tenant_id
    ),
    updated_at = now()
FROM public.accounts a
WHERE a.role != 'super_admin'
  AND a.tenant_id IS NOT NULL
  AND u.email = CASE
                  WHEN a.login_id LIKE '%@%' THEN a.login_id
                  ELSE a.login_id || '@meguree.internal'
                END
  AND (u.raw_app_meta_data->>'tenant_id') IS DISTINCT FROM a.tenant_id::text;
