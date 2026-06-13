-- Migration 043: 小売店の注文履歴・明細・パスワード変更（ログイン制移行 第二弾）
-- 適用方法: Supabase MCP apply_migration もしくは Dashboard > SQL Editor
--
-- 第二弾の範囲: 注文履歴の閲覧・「いつもの注文（再注文）」用の明細取得・ログイン中のパスワード変更。
-- いずれも tenant_id / customer_id は JWT(login_id)→accounts から導出し、
-- 自分の取引先の注文以外は読めない（なりすまし・他店閲覧を排除）。
--
-- ※「忘れてログインできない時のメール再設定」は別途メール基盤が必要なため第二弾の対象外
--   （当面は卸業者が招待リンクを再発行する運用）。本RPCはログイン中の自己変更のみ。

-- ================================================================
-- 1. 自分の注文一覧
-- ================================================================
CREATE OR REPLACE FUNCTION public.get_my_orders()
RETURNS TABLE(order_id uuid, order_code text, order_date date, status text,
              item_count int, subtotal bigint, total bigint)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  WITH me AS (
    SELECT a.tenant_id, a.customer_id
    FROM accounts a
    WHERE a.login_id = (auth.jwt()->'user_metadata'->>'login_id') AND a.role = 'retail'
    LIMIT 1
  )
  SELECT
    o.id, o.order_code, o.order_date, o.status,
    (SELECT count(*) FROM order_items oi WHERE oi.order_id = o.id)::int,
    COALESCE((SELECT sum(oi.unit_price * oi.quantity)
              FROM order_items oi WHERE oi.order_id = o.id), 0)::bigint,
    COALESCE((SELECT sum(oi.unit_price * oi.quantity
                     + round(oi.unit_price * oi.quantity *
                             (CASE WHEN p.is_food THEN 0.08 ELSE 0.10 END)))
              FROM order_items oi JOIN products p ON p.id = oi.product_id
              WHERE oi.order_id = o.id), 0)::bigint
  FROM orders o, me
  WHERE o.tenant_id = me.tenant_id
    AND o.customer_id = me.customer_id
  ORDER BY o.order_date DESC, o.created_at DESC;
$$;

GRANT EXECUTE ON FUNCTION public.get_my_orders() TO authenticated;

-- ================================================================
-- 2. 自分の注文の明細（所有検証つき・再注文/詳細表示に使用）
-- ================================================================
CREATE OR REPLACE FUNCTION public.get_my_order_detail(p_order_id uuid)
RETURNS TABLE(product_id uuid, product_name text, quantity int, unit_price int,
              is_food boolean, display_order int)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  WITH me AS (
    SELECT a.tenant_id, a.customer_id
    FROM accounts a
    WHERE a.login_id = (auth.jwt()->'user_metadata'->>'login_id') AND a.role = 'retail'
    LIMIT 1
  )
  SELECT oi.product_id, p.product_name, oi.quantity, oi.unit_price, p.is_food, oi.display_order
  FROM order_items oi
  JOIN orders o   ON o.id = oi.order_id
  JOIN products p ON p.id = oi.product_id
  , me
  WHERE oi.order_id = p_order_id
    AND o.tenant_id = me.tenant_id
    AND o.customer_id = me.customer_id
  ORDER BY oi.display_order;
$$;

GRANT EXECUTE ON FUNCTION public.get_my_order_detail(uuid) TO authenticated;

-- ================================================================
-- 3. ログイン中のパスワード変更（現在のパスワード検証 → accounts を更新）
--    次回ログインは verify_login（accounts照合）→ sync_auth_user_on_login が
--    auth.users を新パスワードで再同期するため、ここでは accounts のみ更新でよい。
-- ================================================================
CREATE OR REPLACE FUNCTION public.change_my_password(p_current_password text, p_new_password text)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_login text := auth.jwt()->'user_metadata'->>'login_id';
  v_hash  text;
BEGIN
  IF v_login IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_authenticated');
  END IF;
  IF p_new_password IS NULL OR length(p_new_password) < 6 THEN
    RETURN json_build_object('success', false, 'error', 'password_too_short');
  END IF;

  SELECT password_hash INTO v_hash FROM accounts WHERE login_id = v_login;
  IF v_hash IS NULL OR crypt(p_current_password, v_hash) <> v_hash THEN
    RETURN json_build_object('success', false, 'error', 'wrong_current_password');
  END IF;

  UPDATE accounts
  SET password_hash = crypt(p_new_password, gen_salt('bf', 10)), password = ''
  WHERE login_id = v_login;

  RETURN json_build_object('success', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.change_my_password(text, text) TO authenticated;
