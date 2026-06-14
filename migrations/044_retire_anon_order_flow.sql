-- Migration 044: 旧・匿名注文フロー（ログイン不要 order_form.html）の retire（cutover）
-- 適用方法: Supabase MCP apply_migration もしくは Dashboard > SQL Editor
--
-- 背景:
--   ログイン制移行（第一弾/第二弾・PR #285/#286）でログイン式注文（shop.html）に一本化。
--   order_form.html はログイン画面へ転送するだけのページに置換済み（QR未配布のため実害なし）。
--   ここでは旧フローが使っていた匿名(anon)用RPCの実行権限を剥奪し、API直叩きでも
--   匿名注文・匿名での商品/卸価格/取引先名取得ができないようにする（攻撃面の縮小）。
--
-- 影響なし（残す匿名アクセス）:
--   - 問い合わせ（inquiries の anon insert）
--   - 卸業者の招待登録（get_invitation_by_token / register_invited_account）
--   - 小売店の招待登録（get_retail_invitation_by_token / register_retail_account）
--   ※ これらは触らない。
--
-- ログイン式注文（shop.html・retail/authenticated）は get_my_products / get_my_pricing /
--   get_my_customer / create_my_order を使うため、本剥奪の影響を受けない。

-- 旧 order_form.html 専用だった匿名RPCの実行権限を剥奪
REVOKE EXECUTE ON FUNCTION public.create_anon_order(uuid, uuid, text, date, text, jsonb, text, text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_products_for_tenant(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_pricing_for_customer(uuid, uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_customer_name_by_id(uuid, uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_customer_id_by_name(text, uuid) FROM anon;

-- count_today_orders は注文番号採番でログイン式注文画面(authenticated)が使うため、
-- authenticated 実行権限を保証したうえで anon からは剥奪する。
GRANT EXECUTE ON FUNCTION public.count_today_orders() TO authenticated;
REVOKE EXECUTE ON FUNCTION public.count_today_orders() FROM anon;
