-- Migration: パスワードをbcryptに移行
-- 適用方法: Supabase Dashboard > SQL Editor に貼り付けて実行
-- 前提: accountsテーブルに password（SHA-256/平文）と password_hash（bcrypt用・現在空）カラムが存在

-- pgcrypto 拡張を有効化（bcrypt用）
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ============================================================
-- verify_login RPC を更新
-- 優先順位: bcrypt → SHA-256 → 平文（移行期フォールバック）
-- 照合成功時に自動でbcryptへ移行
-- ============================================================
CREATE OR REPLACE FUNCTION verify_login(
  p_login_id text,
  p_password  text
)
RETURNS TABLE(login_id text, name text, role text)
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_row   accounts%ROWTYPE;
  v_valid boolean := false;
BEGIN
  SELECT * INTO v_row FROM accounts WHERE accounts.login_id = p_login_id;
  IF NOT FOUND THEN RETURN; END IF;

  IF v_row.password_hash IS NOT NULL AND v_row.password_hash <> '' THEN
    -- bcrypt照合
    v_valid := (v_row.password_hash = crypt(p_password, v_row.password_hash));
  ELSIF v_row.password = encode(digest(p_password, 'sha256'), 'hex') THEN
    -- SHA-256照合 → bcryptへ自動移行
    v_valid := true;
    UPDATE accounts SET password_hash = crypt(p_password, gen_salt('bf', 10)), password = ''
    WHERE accounts.login_id = p_login_id;
  ELSIF v_row.password = p_password THEN
    -- 平文フォールバック → bcryptへ自動移行
    v_valid := true;
    UPDATE accounts SET password_hash = crypt(p_password, gen_salt('bf', 10)), password = ''
    WHERE accounts.login_id = p_login_id;
  END IF;

  IF v_valid THEN
    RETURN QUERY SELECT v_row.login_id, v_row.name, v_row.role;
  END IF;
END;
$$;

-- ============================================================
-- change_password RPC を更新
-- 現パスワードを照合してから新パスワードをbcryptで保存
-- ============================================================
CREATE OR REPLACE FUNCTION change_password(
  p_login_id         text,
  p_current_password text,
  p_new_password     text
)
RETURNS json
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_row   accounts%ROWTYPE;
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
  SET password_hash = crypt(p_new_password, gen_salt('bf', 10)),
      password      = ''
  WHERE accounts.login_id = p_login_id;

  RETURN json_build_object('success', true);
END;
$$;
