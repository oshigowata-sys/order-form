-- 063: ログイン前（anon）から不要な関数の実行権限を取り上げる
--
-- 背景（2026-10-22 月1セキュリティ点検）
--   Supabase Advisor の 0028 (anon_security_definer_function_executable) で
--   「ログインしていない相手から呼べる SECURITY DEFINER 関数が15本」と警告。
--   内訳を実査した結果：
--     必要9本 = ログイン3本（verify_login / sync_auth_user_on_login /
--                            sync_auth_super_admin_on_login）
--             + 招待リンク6本（get_*_invitation_by_token ×3 /
--                              register_*_account ×3）
--     不要6本 = 下記5本 + get_tenant_plan
--
--   本migrationでは **5本だけ** 取り上げる。
--   get_tenant_plan は login.html が「ログイン成功後なのに匿名キーのまま」
--   呼んでいるため、先に取り上げると全テナントのプラン判定が
--   黙って 'standard' に落ちる（login.html の fallback）。
--   → 共通版・父親版の login.html を修正してから別migrationで取り上げる。
--
-- 影響がないことの根拠（2026-10-22 実コードを grep して確認）
--   generate_quotation_number : quotation.html が sbFetch 経由＝JWTを送る（共通版・父親版とも）
--   get_my_tax_rates          : shop.html が sbFetch 経由＝JWTを送る（共通版のみ・父親版は未使用）
--   tax_rate_for              : get_my_orders の内部からのみ呼ばれる。
--                               SECURITY DEFINER 内の呼び出しは所有者権限で走るため
--                               anon のEXECUTE有無に影響されない
--   handle_auth_user_signup   : トリガー専用（pg_trigger に登録あり）。
--   handle_inquiry_insert       REST から直接呼んでも NEW/TG_OP が無く失敗する
--
-- add-only 適合：カラム・関数の追加/削除/改名/引数変更を一切行わない。
--   権限(GRANT/REVOKE)のみの変更＝db-contract のスキーマ形状スナップショットは不変。
--   （スナップショットは information_schema.columns と pg_proc の署名のみを見るため、
--     権限変更は定義上ハッシュを変えない。適用前後の md5 一致で実証する）
--
-- ⚠️⚠️ 【重要・2026-10-22 追記】このmigrationは**効果がなかった**。064 が正。
--   適用後に has_function_privilege('anon', ...) を確認したら **5本とも true のまま**だった。
--   原因＝anon個別のGRANTではなく、**PUBLIC（全員）への既定EXECUTE**が効いていた。
--   PostgreSQL は CREATE FUNCTION 時に自動で `GRANT EXECUTE ... TO PUBLIC` を付けるため、
--   proacl に `=X/postgres`（grantee空＝PUBLIC）が入る。anon は PUBLIC に含まれるので
--   `REVOKE ... FROM anon` だけでは通り続ける。
--   → **`REVOKE EXECUTE ... FROM PUBLIC` が必要**。migration 064 で実施。
--   ※調査時のACL確認クエリが pg_get_userbyid(grantee) を 'public' と比較していたが、
--     PUBLIC は grantee=0 で pg_get_userbyid(0) は 'public' を返さないため見落とした。
--     今後ACLを見るときは **proacl の生の値**か has_function_privilege() を使う。
--   このmigration自体は無害（get_tenant_plan/verify_login 以外に anon 個別GRANTは無く、
--   実質なにも変わっていない）ため取り消さず記録として残す。
--
-- 戻し方（万一画面が壊れた場合）
--   GRANT EXECUTE ON FUNCTION public.<関数名>(<引数型>) TO anon;
--   を実行すれば即座に元に戻る。データは一切動かさない。

REVOKE EXECUTE ON FUNCTION public.generate_quotation_number(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_my_tax_rates(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.tax_rate_for(uuid, date, boolean) FROM anon;
REVOKE EXECUTE ON FUNCTION public.handle_auth_user_signup() FROM anon;
REVOKE EXECUTE ON FUNCTION public.handle_inquiry_insert() FROM anon;
