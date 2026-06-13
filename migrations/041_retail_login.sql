-- Migration 041: 注文フォームのログイン制移行（第一弾）— 小売店ログインの土台
-- 適用方法: Supabase MCP apply_migration もしくは Dashboard > SQL Editor
--
-- 目的:
--   小売店(retail)がログインして「自分の取引先」としてのみ注文できる土台を作る。
--   2026-06-13 Wata決定（注文フォームのログイン制移行・第一弾＝ログインして注文）に対応。
--
-- 設計の肝:
--   (1) なりすまし排除: 注文RPC create_my_order は tenant_id/customer_id を
--       クライアントから受け取らず、署名済みJWTの login_id クレーム → accounts から導出する。
--   (2) データ分離: retail のJWTには tenant_id クレームを載せない（sync_auth_user_on_login）。
--       既存の tenant 全体ポリシー（"*_tenant_all" = tenant_id::text = jwt_tenant_id()）は
--       jwt_tenant_id() が NULL の retail に対し常に false となり、他店・卸業者データは構造的に不可視。
--       retail は専用 SECURITY DEFINER RPC（get_my_*・create_my_order）経由でのみ自分の範囲に触れる。
--   (3) 完全分離: 既存の卸業者向け招待 register_invited_account（migration 007）とは別RPC。
--       小売店登録は tenants/settings を一切作らない・触らない。
--
-- 後方互換（厳守）:
--   すべて追加のみ。既存列・既存関数の引数の削除/改名なし。
--   verify_login は戻り値に customer_id を1列「追加」（呼び出し側は列名で参照するため安全）。
--   sync_auth_user_on_login は引数不変、メタデータに customer_id を追加（retailのみ tenant_id を空に）。
--   既存の admin / super_admin の挙動は不変。

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ================================================================
-- 1. invitations に小売店招待用の列を追加
--    （既存の卸業者招待は両列 NULL のまま＝従来動作を維持）
-- ================================================================
ALTER TABLE invitations ADD COLUMN IF NOT EXISTS customer_id    uuid;
ALTER TABLE invitations ADD COLUMN IF NOT EXISTS intended_role  text;

COMMENT ON COLUMN invitations.customer_id   IS '小売店招待の対象取引先。卸業者招待ではNULL';
COMMENT ON COLUMN invitations.intended_role IS '発行されるアカウントの役割。小売店招待は ''retail''、卸業者招待はNULL';

-- ================================================================
-- 2. verify_login に customer_id を追加（戻り値に1列追加・他は不変）
-- ================================================================
DROP FUNCTION IF EXISTS verify_login(text, text);

CREATE OR REPLACE FUNCTION verify_login(
  p_login_id text,
  p_password  text
)
RETURNS TABLE(login_id text, name text, role text, tenant_id uuid, customer_id uuid)
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_row   accounts%ROWTYPE;
  v_valid boolean := false;
BEGIN
  SELECT * INTO v_row FROM accounts WHERE accounts.login_id = p_login_id;
  IF NOT FOUND THEN RETURN; END IF;

  IF v_row.password_hash IS NOT NULL AND v_row.password_hash <> '' THEN
    v_valid := (v_row.password_hash = crypt(p_password, v_row.password_hash));
  ELSIF v_row.password = encode(digest(p_password, 'sha256'), 'hex') THEN
    v_valid := true;
    UPDATE accounts SET password_hash = crypt(p_password, gen_salt('bf', 10)), password = ''
    WHERE accounts.login_id = p_login_id;
  ELSIF v_row.password = p_password THEN
    v_valid := true;
    UPDATE accounts SET password_hash = crypt(p_password, gen_salt('bf', 10)), password = ''
    WHERE accounts.login_id = p_login_id;
  END IF;

  IF v_valid THEN
    RETURN QUERY SELECT v_row.login_id, v_row.name, v_row.role, v_row.tenant_id, v_row.customer_id;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION verify_login(text, text) TO anon, authenticated;

-- ================================================================
-- 3. sync_auth_user_on_login: メタデータに customer_id を追加
--    retail は tenant_id クレームを空にして全体ポリシーに乗れないようにする
--    （migration 016 の定義をベースに最小差分）
-- ================================================================
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
    v_tenant_claim uuid;
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

    -- retail には tenant_id クレームを与えない（既存 *_tenant_all ポリシーに乗れない＝他店データ不可視）
    v_tenant_claim := CASE WHEN v_account.role = 'retail' THEN NULL ELSE v_account.tenant_id END;

    v_app_meta := jsonb_build_object(
      'provider', 'email',
      'providers', jsonb_build_array('email'),
      'login_id', v_account.login_id,
      'name', v_account.name,
      'role', v_account.role,
      'tenant_id', v_tenant_claim,
      'customer_id', v_account.customer_id
    );

    v_user_meta := jsonb_build_object(
      'login_id', v_account.login_id,
      'name', v_account.name,
      'role', v_account.role,
      'tenant_id', v_tenant_claim,
      'customer_id', v_account.customer_id
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

-- ================================================================
-- 4. 小売店招待の発行（ログイン済み卸業者=admin が呼ぶ）
--    tenant は JWT から導出。対象取引先が自テナント所属であることを検証。
-- ================================================================
CREATE OR REPLACE FUNCTION public.create_retail_invitation(p_customer_id uuid)
RETURNS TABLE(token text, expires_at timestamptz)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant   uuid := NULLIF(auth.jwt()->'user_metadata'->>'tenant_id','')::uuid;
  v_role     text := auth.jwt()->'user_metadata'->>'role';
  v_cust_tid uuid;
  v_token    text;
  v_expires  timestamptz := now() + interval '14 days';
BEGIN
  IF v_tenant IS NULL OR v_role NOT IN ('admin','super_admin') THEN
    RAISE EXCEPTION 'not authorized to issue retail invitations';
  END IF;

  SELECT tenant_id INTO v_cust_tid FROM customers WHERE id = p_customer_id;
  IF v_cust_tid IS NULL OR v_cust_tid <> v_tenant THEN
    RAISE EXCEPTION 'customer % does not belong to your tenant', p_customer_id;
  END IF;

  v_token := encode(gen_random_bytes(24), 'hex');

  INSERT INTO invitations (token, tenant_id, customer_id, intended_role, expires_at)
  VALUES (v_token, v_tenant, p_customer_id, 'retail', v_expires);

  RETURN QUERY SELECT v_token, v_expires;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_retail_invitation(uuid) TO authenticated;

-- ================================================================
-- 5. 小売店招待のプレビュー（登録ページが会社名表示に使う・ログイン不要）
-- ================================================================
CREATE OR REPLACE FUNCTION public.get_retail_invitation_by_token(p_token text)
RETURNS TABLE(customer_id uuid, company_name text, expires_at timestamptz)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT i.customer_id, c.company_name, i.expires_at
  FROM invitations i
  JOIN customers c ON c.id = i.customer_id
  WHERE i.token = p_token
    AND i.used_at IS NULL
    AND i.expires_at > now()
    AND i.intended_role = 'retail'
  LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION public.get_retail_invitation_by_token(text) TO anon, authenticated;

-- ================================================================
-- 6. 小売店アカウント登録（招待トークンから・ログイン不要）
--    tenants/settings には一切触れない（卸業者招待との決定的な違い）
-- ================================================================
CREATE OR REPLACE FUNCTION public.register_retail_account(
  p_token text,
  p_login_id text,
  p_password text,
  p_terms_version text DEFAULT NULL,
  p_privacy_version text DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_inv  invitations%rowtype;
  v_name text;
BEGIN
  IF p_token IS NULL OR length(trim(p_token)) = 0 THEN
    RETURN json_build_object('success', false, 'error', 'invalid_token');
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
    AND intended_role = 'retail'
  LIMIT 1
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'invalid_or_expired');
  END IF;

  IF EXISTS (SELECT 1 FROM accounts WHERE login_id = p_login_id) THEN
    RETURN json_build_object('success', false, 'error', 'login_id_exists');
  END IF;

  SELECT company_name INTO v_name FROM customers WHERE id = v_inv.customer_id;

  INSERT INTO accounts (
    login_id, name, role, password, password_hash, tenant_id, customer_id,
    consented_terms_version, consented_privacy_version, consented_at
  )
  VALUES (
    p_login_id, v_name, 'retail', '', crypt(p_password, gen_salt('bf', 10)),
    v_inv.tenant_id, v_inv.customer_id,
    p_terms_version, p_privacy_version, now()
  );

  UPDATE invitations SET used_at = now() WHERE id = v_inv.id;

  RETURN json_build_object('success', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.register_retail_account(text, text, text, text, text) TO anon, authenticated;

-- ================================================================
-- 7. retail 自身の取引先・商品・卸価格を返す RPC（JWTから自分を導出）
--    列構成は既存 get_products_for_tenant / get_pricing_for_customer と完全一致
-- ================================================================
CREATE OR REPLACE FUNCTION public.get_my_customer()
RETURNS TABLE(customer_id uuid, company_name text)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT a.customer_id, c.company_name
  FROM accounts a
  JOIN customers c ON c.id = a.customer_id
  WHERE a.login_id = (auth.jwt()->'user_metadata'->>'login_id')
    AND a.role = 'retail'
  LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION public.get_my_customer() TO authenticated;

CREATE OR REPLACE FUNCTION public.get_my_products()
RETURNS TABLE(id uuid, product_code text, product_name text, price integer, list_price integer, category text, is_food boolean, image_url text)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT p.id, p.product_code, p.product_name, p.price, p.list_price, p.category, p.is_food, p.image_url
  FROM products p
  WHERE p.tenant_id = (
    SELECT a.tenant_id FROM accounts a
    WHERE a.login_id = (auth.jwt()->'user_metadata'->>'login_id') AND a.role = 'retail'
    LIMIT 1
  )
  ORDER BY p.category NULLS LAST, p.product_name;
$$;

GRANT EXECUTE ON FUNCTION public.get_my_products() TO authenticated;

CREATE OR REPLACE FUNCTION public.get_my_pricing()
RETURNS TABLE(product_id uuid, rate numeric, wholesale_price integer)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT pr.product_id, pr.rate, pr.wholesale_price
  FROM pricing pr
  JOIN accounts a
    ON a.login_id = (auth.jwt()->'user_metadata'->>'login_id') AND a.role = 'retail'
  WHERE pr.tenant_id = a.tenant_id
    AND pr.customer_id = a.customer_id;
$$;

GRANT EXECUTE ON FUNCTION public.get_my_pricing() TO authenticated;

-- ================================================================
-- 8. 認証版の注文登録（なりすまし排除の本体）
--    tenant_id / customer_id はクライアントから受け取らず JWT→accounts から導出。
--    明細形状・display_order の採番は create_anon_order（migration 040）と同じ。
-- ================================================================
CREATE OR REPLACE FUNCTION public.create_my_order(
  p_order_code text,
  p_order_date date,
  p_status text,
  p_items jsonb,
  p_input_contact_name text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_login     text := auth.jwt()->'user_metadata'->>'login_id';
  v_tenant_id uuid;
  v_customer_id uuid;
  v_order_id  uuid;
  v_item      jsonb;
  v_idx       int;
  v_bad_count int;
BEGIN
  IF v_login IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  -- 署名済みJWTの login_id から自分の取引先を確定（クライアント値は信用しない）
  SELECT a.tenant_id, a.customer_id
    INTO v_tenant_id, v_customer_id
  FROM accounts a
  WHERE a.login_id = v_login AND a.role = 'retail'
  LIMIT 1;

  IF v_tenant_id IS NULL OR v_customer_id IS NULL THEN
    RAISE EXCEPTION 'no retail customer bound to this account';
  END IF;

  -- 明細の各 product_id が自テナント所属であることを検証
  SELECT COUNT(*) INTO v_bad_count
  FROM jsonb_array_elements(p_items) AS item
  WHERE NOT EXISTS (
    SELECT 1 FROM products
    WHERE id = (item->>'product_id')::uuid
      AND tenant_id = v_tenant_id
  );
  IF v_bad_count > 0 THEN
    RAISE EXCEPTION 'some products do not belong to tenant %', v_tenant_id;
  END IF;

  INSERT INTO orders (
    tenant_id, customer_id, order_code, order_date, status,
    input_company_name, input_contact_name
  )
  VALUES (
    v_tenant_id, v_customer_id, p_order_code, p_order_date, p_status,
    NULL, p_input_contact_name
  )
  RETURNING id INTO v_order_id;

  FOR v_item, v_idx IN
    SELECT t.elem, (t.ord - 1)::int
    FROM jsonb_array_elements(p_items) WITH ORDINALITY AS t(elem, ord)
  LOOP
    INSERT INTO order_items (order_id, product_id, quantity, unit_price, display_order)
    VALUES (
      v_order_id,
      (v_item->>'product_id')::uuid,
      (v_item->>'quantity')::int,
      (v_item->>'unit_price')::int,
      v_idx
    );
  END LOOP;

  RETURN v_order_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_my_order(text, date, text, jsonb, text) TO authenticated;
