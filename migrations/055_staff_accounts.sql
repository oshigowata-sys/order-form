-- Migration 055: 複数人ログイン（スタッフアカウント）— プラン制限 第3弾
-- 適用方法: Supabase MCP apply_migration もしくは Dashboard > SQL Editor
--
-- 目的:
--   スタンダード以上のプランで、1テナント（卸業者）に複数の管理アカウント（admin）を
--   発行できるようにする。発行方式＝招待リンク式（案ア・Wata 2026-06-25）。
--   スタッフ本人がリンクで自分の login_id / パスワードを設定する（adminはパスワードを握らない）。
--
-- 設計の肝:
--   (1) accounts の一意制約は login_id のみ。1テナント複数アカウントは既に構造的に可能
--       （admin1＋retail N が同一 tenant_id を共有）。本migrationは追加のみ＝制約は一切触らない。
--   (2) 既存の小売店招待（migration 041 create_retail_invitation / register_retail_account）に倣う。
--       スタッフ招待は intended_role='admin'・customer_id NULL。tenants/settings は作らない・触らない。
--   (3) ログインは既存の verify_login / sync_auth_user_on_login がそのまま機能（login_id単位）。
--       追加した admin は role='admin' なので JWT に tenant_id クレームが載り、フルアクセス（権限差なし＝案B）。
--
-- 後方互換（厳守・add-only）:
--   すべて新規 CREATE FUNCTION のみ。既存テーブル・列・制約・関数の削除/改名/型/引数/戻り変更なし。
--   既存の卸業者ログイン・小売店ログイン・父親の凍結版に影響しない。

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ================================================================
-- 1. スタッフ招待の発行（ログイン中 admin が呼ぶ）
--    tenant は JWT から導出。intended_role='admin'・customer_id は使わない。
-- ================================================================
CREATE OR REPLACE FUNCTION public.create_staff_invitation()
RETURNS TABLE(token text, expires_at timestamptz)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions  -- pgcrypto(gen_random_bytes)はextensionsスキーマ（migration 042の教訓）
AS $$
DECLARE
  v_tenant  uuid := NULLIF(auth.jwt()->'user_metadata'->>'tenant_id','')::uuid;
  v_role    text := auth.jwt()->'user_metadata'->>'role';
  v_token   text;
  v_expires timestamptz := now() + interval '14 days';
BEGIN
  IF v_tenant IS NULL OR v_role NOT IN ('admin','super_admin') THEN
    RAISE EXCEPTION 'not authorized to issue staff invitations';
  END IF;

  v_token := encode(gen_random_bytes(24), 'hex');

  INSERT INTO invitations (token, tenant_id, intended_role, expires_at)
  VALUES (v_token, v_tenant, 'admin', v_expires);

  RETURN QUERY SELECT v_token, v_expires;
END;
$$;

-- Supabaseは新規関数を anon/authenticated に直接GRANTするため、PUBLICだけでなく anon も明示REVOKE（migration 045の教訓）
REVOKE EXECUTE ON FUNCTION public.create_staff_invitation() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_staff_invitation() TO authenticated;

-- ================================================================
-- 2. スタッフ招待のプレビュー（登録ページが会社名表示に使う・ログイン不要）
--    会社名は settings 優先、無ければ tenants.name。
-- ================================================================
CREATE OR REPLACE FUNCTION public.get_staff_invitation_by_token(p_token text)
RETURNS TABLE(company_name text, expires_at timestamptz)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(s.company_name, t.name) AS company_name, i.expires_at
  FROM invitations i
  JOIN tenants t       ON t.id = i.tenant_id
  LEFT JOIN settings s ON s.tenant_id = i.tenant_id
  WHERE i.token = p_token
    AND i.used_at IS NULL
    AND i.expires_at > now()
    AND i.intended_role = 'admin'
  LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION public.get_staff_invitation_by_token(text) TO anon, authenticated;

-- ================================================================
-- 3. スタッフアカウント登録（招待トークンから・ログイン不要）
--    既存テナントに role='admin' を追加。tenants/settings には触れない。
-- ================================================================
CREATE OR REPLACE FUNCTION public.register_staff_account(
  p_token text,
  p_login_id text,
  p_password text,
  p_name text DEFAULT NULL,
  p_terms_version text DEFAULT NULL,
  p_privacy_version text DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions  -- pgcrypto(crypt/gen_salt)はextensionsスキーマ（migration 042の教訓）
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
    AND intended_role = 'admin'
  LIMIT 1
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'invalid_or_expired');
  END IF;

  IF EXISTS (SELECT 1 FROM accounts WHERE login_id = p_login_id) THEN
    RETURN json_build_object('success', false, 'error', 'login_id_exists');
  END IF;

  v_name := COALESCE(NULLIF(trim(p_name), ''), p_login_id);

  INSERT INTO accounts (
    login_id, name, role, password, password_hash, tenant_id,
    consented_terms_version, consented_privacy_version, consented_at
  )
  VALUES (
    p_login_id, v_name, 'admin', '', crypt(p_password, gen_salt('bf', 10)),
    v_inv.tenant_id,
    p_terms_version, p_privacy_version, now()
  );

  UPDATE invitations SET used_at = now() WHERE id = v_inv.id;

  RETURN json_build_object('success', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.register_staff_account(text, text, text, text, text, text) TO anon, authenticated;

-- ================================================================
-- 4. 自テナントの管理アカウント一覧（admin限定・password_hashは返さない）
-- ================================================================
CREATE OR REPLACE FUNCTION public.list_tenant_accounts()
RETURNS TABLE(login_id text, name text, role text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant uuid := NULLIF(auth.jwt()->'user_metadata'->>'tenant_id','')::uuid;
  v_role   text := auth.jwt()->'user_metadata'->>'role';
BEGIN
  IF v_tenant IS NULL OR v_role NOT IN ('admin','super_admin') THEN
    RAISE EXCEPTION 'not authorized';
  END IF;

  RETURN QUERY
  SELECT a.login_id, a.name, a.role
  FROM accounts a
  WHERE a.tenant_id = v_tenant
    AND a.role = 'admin'
  ORDER BY a.login_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.list_tenant_accounts() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_tenant_accounts() TO authenticated;

-- ================================================================
-- 5. スタッフ削除（admin限定・自分/最後の1人は不可・同一テナント検証）
--    対応する auth.users 行も掃除する。
-- ================================================================
CREATE OR REPLACE FUNCTION public.delete_staff_account(p_login_id text)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $$
DECLARE
  v_tenant   uuid := NULLIF(auth.jwt()->'user_metadata'->>'tenant_id','')::uuid;
  v_role     text := auth.jwt()->'user_metadata'->>'role';
  v_self     text := auth.jwt()->'user_metadata'->>'login_id';
  v_target   accounts%rowtype;
  v_admin_cnt int;
  v_email    text;
BEGIN
  IF v_tenant IS NULL OR v_role NOT IN ('admin','super_admin') THEN
    RETURN json_build_object('success', false, 'error', 'not_authorized');
  END IF;
  IF p_login_id IS NULL OR length(trim(p_login_id)) = 0 THEN
    RETURN json_build_object('success', false, 'error', 'invalid_target');
  END IF;
  IF p_login_id = v_self THEN
    RETURN json_build_object('success', false, 'error', 'cannot_delete_self');
  END IF;

  SELECT * INTO v_target
  FROM accounts
  WHERE login_id = p_login_id
    AND tenant_id = v_tenant
    AND role = 'admin'
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'not_found');
  END IF;

  SELECT COUNT(*) INTO v_admin_cnt
  FROM accounts WHERE tenant_id = v_tenant AND role = 'admin';
  IF v_admin_cnt <= 1 THEN
    RETURN json_build_object('success', false, 'error', 'last_admin');
  END IF;

  -- auth.users の対応行を掃除（email は sync_auth_user_on_login と同じ導出）
  v_email := CASE WHEN p_login_id LIKE '%@%' THEN p_login_id ELSE p_login_id || '@meguree.internal' END;
  DELETE FROM auth.users WHERE email = v_email;

  DELETE FROM accounts WHERE login_id = p_login_id AND tenant_id = v_tenant AND role = 'admin';

  RETURN json_build_object('success', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.delete_staff_account(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_staff_account(text) TO authenticated;
