-- Migration: verify_login に tenant_id を追加
-- 適用方法: Supabase Dashboard > SQL Editor に貼り付けて実行

-- 戻り値の型変更のため一度DROP
DROP FUNCTION IF EXISTS verify_login(text, text);

CREATE OR REPLACE FUNCTION verify_login(
  p_login_id text,
  p_password  text
)
RETURNS TABLE(login_id text, name text, role text, tenant_id uuid)
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
    RETURN QUERY SELECT v_row.login_id, v_row.name, v_row.role, v_row.tenant_id;
  END IF;
END;
$$;
