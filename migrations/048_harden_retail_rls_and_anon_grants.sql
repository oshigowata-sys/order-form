-- Migration 048: retail_memberships の RLS 有効化 ＋ 認証専用RPCの anon/PUBLIC 露出を剥奪
--
-- 背景:
--   (A) migration 046 で新設した retail_memberships が RLS 無効のまま稼働しており、
--       anon/authenticated ロールに全行が露出していた（Supabaseアドバイザリ critical）。
--       設計意図は「RLSは付けず SECURITY DEFINER RPC 経由でのみ読み書き」だったが、
--       RLS 有効化を忘れていた＝有効化すれば意図どおり RPC 専用アクセスになる。
--   (B) 046 で get_my_* / create_my_order 等を DROP→CREATE した際、PostgreSQL の
--       「CREATE FUNCTION は EXECUTE を PUBLIC に既定付与」仕様により anon にも実行権が
--       戻っていた（migration 044/045 と同じ穴）。これらは認証必須RPCのため anon 不要。
--   (C) change_password は内部にロールガードが無く、anon から任意 login_id に対して
--       「現在パスワード照合つきパスワード変更」を試せる状態（未認証ブルートフォース面）。
--
-- 方針: すべて追加/権限変更のみ（後方互換）。SECURITY DEFINER 関数は所有者(postgres)権限で
--       動くため、RLS 有効化・authenticated 限定にしても RPC 経由の正規フローは無影響。

-- ================================================================
-- (A) retail_memberships の RLS を有効化（ポリシーは付けない＝直接アクセスは全拒否）
--     直接の REST アクセスを二重に塞ぐため anon/authenticated の直接権限も剥奪。
--     正規アクセスは SECURITY DEFINER RPC（所有者権限）経由のみ。
-- ================================================================
ALTER TABLE public.retail_memberships ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.retail_memberships FROM anon, authenticated;

-- ================================================================
-- (B) 認証必須 retail RPC：PUBLIC/anon の EXECUTE を剥奪し authenticated のみに限定
--     （anon が呼んでも JWT 由来の login_id が無く実害は無かったが、面を削る）
-- ================================================================
REVOKE EXECUTE ON FUNCTION public.retail_my_binding(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.retail_my_binding(uuid) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.get_my_memberships() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_my_memberships() TO authenticated;

REVOKE EXECUTE ON FUNCTION public.get_my_customer(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_my_customer(uuid) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.get_my_products(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_my_products(uuid) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.get_my_pricing(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_my_pricing(uuid) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.get_my_orders(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_my_orders(uuid) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.get_my_order_detail(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_my_order_detail(uuid) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.create_my_order(text, date, text, jsonb, text, uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.create_my_order(text, date, text, jsonb, text, uuid) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.link_retail_membership(text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.link_retail_membership(text) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.change_my_password(text, text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.change_my_password(text, text) TO authenticated;

-- ================================================================
-- (C) パスワード変更（login_id 引数版・ロールガード無し）を未認証から切り離す
--     正規利用は管理画面（admin/super_admin の認証済みJWT）からのみ。
-- ================================================================
REVOKE EXECUTE ON FUNCTION public.change_password(text, text, text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.change_password(text, text, text) TO authenticated;

-- ================================================================
-- (D) 管理者専用RPC（内部ガード有りだが anon 露出は不要）：authenticated のみに限定
-- ================================================================
REVOKE EXECUTE ON FUNCTION public.create_retail_invitation(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.create_retail_invitation(uuid) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.delete_tenant_cascade(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.delete_tenant_cascade(uuid) TO authenticated;

-- 注意（このマイグレーションでは触らない・別途検討）:
--   * diagnose_invited_account_registration … 本番不要の診断用デッドコード。削除候補。
--   * get_tenant_plan(anon) … plan文字列のみ返す低機微。招待/注文導線の利用有無を確認のうえ判断。
--   * 匿名で残すべき関数（verify_login / sync_* / register_invited_account /
--     register_retail_account / get_*_invitation_by_token / handle_inquiry_insert /
--     jwt_role / jwt_tenant_id 等）は意図どおり anon を維持。
