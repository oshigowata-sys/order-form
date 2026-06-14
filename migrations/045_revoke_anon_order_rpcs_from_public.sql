-- Migration 045: 旧・匿名注文RPCの実行権限を PUBLIC からも剥奪（044の不足を修正）
-- 適用方法: Supabase MCP apply_migration もしくは Dashboard > SQL Editor
--
-- 背景:
--   044 で anon から REVOKE したが、PostgreSQL では関数作成時に EXECUTE が
--   既定で PUBLIC に付与されるため、anon は PUBLIC 経由で引き続き実行できていた。
--   ここで PUBLIC（および anon / authenticated）から明示的に剥奪して完全に閉じる。
--
-- 対象関数はいずれも現在どの画面からも呼ばれていない（order_form.html は
--   ログイン画面への転送ページに置換済み）。ログイン式注文(shop.html)は
--   get_my_products / get_my_pricing / get_my_customer / create_my_order を使う。
--
-- count_today_orders だけは shop.html（authenticated）が注文番号採番に使うため、
--   authenticated には残し、PUBLIC / anon からのみ剥奪する。

REVOKE EXECUTE ON FUNCTION public.create_anon_order(uuid, uuid, text, date, text, jsonb, text, text) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.get_products_for_tenant(uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.get_pricing_for_customer(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.get_customer_name_by_id(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.get_customer_id_by_name(text, uuid) FROM PUBLIC, anon, authenticated;

REVOKE EXECUTE ON FUNCTION public.count_today_orders() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.count_today_orders() TO authenticated;
