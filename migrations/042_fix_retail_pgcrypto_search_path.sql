-- Migration 042: 小売店招待RPCの search_path 修正
-- 適用方法: Supabase MCP apply_migration もしくは Dashboard > SQL Editor
--
-- 背景:
--   041 で作成した create_retail_invitation / register_retail_account は
--   SET search_path = public のみだったため、pgcrypto 関数（gen_random_bytes /
--   crypt / gen_salt は extensions スキーマに存在）を解決できず
--   "function gen_random_bytes(integer) does not exist" で失敗していた。
--   sync_auth_user_on_login 等の既存関数は search_path に extensions を含めている。
--
-- 対応: 両関数の search_path に extensions を追加（定義内容は 041 と同一）。

CREATE OR REPLACE FUNCTION public.create_retail_invitation(p_customer_id uuid)
RETURNS TABLE(token text, expires_at timestamptz)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
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
SET search_path = public, extensions
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
