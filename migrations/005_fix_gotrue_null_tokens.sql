-- GoTrue が confirmation_token 等に NULL があると
-- "converting NULL to string is unsupported" で 500 を返すため '' に統一する
-- 参照: auth ログ 2026-04-26 のエラー

UPDATE auth.users
SET
  confirmation_token      = COALESCE(confirmation_token, ''),
  recovery_token          = COALESCE(recovery_token, ''),
  email_change_token_new  = COALESCE(email_change_token_new, ''),
  email_change            = COALESCE(email_change, '')
WHERE
  confirmation_token IS NULL
  OR recovery_token IS NULL
  OR email_change_token_new IS NULL
  OR email_change IS NULL;

-- sync_auth_user_on_login を再作成：INSERT/UPDATE 時に必須トークンを '' で初期化
CREATE OR REPLACE FUNCTION public.sync_auth_user_on_login(
  p_login_id text,
  p_password text
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_account  accounts%rowtype;
  v_email    text;
  v_hash     text;
  v_uid      uuid;
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

  v_hash := crypt(p_password, gen_salt('bf', 10));

  UPDATE auth.users
  SET
    encrypted_password      = v_hash,
    email_confirmed_at      = COALESCE(email_confirmed_at, now()),
    confirmation_token      = COALESCE(confirmation_token, ''),
    recovery_token          = COALESCE(recovery_token, ''),
    email_change_token_new  = COALESCE(email_change_token_new, ''),
    email_change            = COALESCE(email_change, ''),
    raw_user_meta_data      = jsonb_build_object(
      'login_id',  v_account.login_id,
      'name',      v_account.name,
      'role',      v_account.role,
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
      '', '',
      '', '',
      '{"provider":"email","providers":["email"]}',
      jsonb_build_object(
        'login_id',  v_account.login_id,
        'name',      v_account.name,
        'role',      v_account.role,
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

GRANT EXECUTE ON FUNCTION public.sync_auth_user_on_login(text, text) TO anon, authenticated, service_role;
