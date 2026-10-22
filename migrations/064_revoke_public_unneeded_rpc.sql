-- 064: ログイン前から呼べる不要な関数を、PUBLIC（全員）から取り上げる
--      ※063 は対象を anon 個別にしていたため効果が無かった。こちらが正。
--
-- なぜ PUBLIC なのか
--   PostgreSQL は CREATE FUNCTION 時に自動で `GRANT EXECUTE ... TO PUBLIC` を付ける。
--   proacl に `=X/postgres`（grantee が空＝PUBLIC）として入る。
--   Supabase の anon ロールは PUBLIC に含まれるため、anon だけ REVOKE しても通り続ける。
--   → 既定の PUBLIC を外し、必要なロールにだけ明示的に GRANT するのが正しい形。
--   先例：delete_tenant_cascade は既に PUBLIC が外れている
--         （proacl = {postgres=X, authenticated=X, service_role=X}）＝この形に揃える。
--
-- 対象5本（いずれも「ログイン前に呼ぶ必要が無い」ことを実コードで確認済み・2026-10-22）
--   generate_quotation_number : quotation.html が sbFetch＝JWT送信（共通版・父親版とも）
--   get_my_tax_rates          : shop.html が sbFetch＝JWT送信（共通版のみ）
--   tax_rate_for              : get_my_orders の内部呼び出しのみ。SECURITY DEFINER 内は
--                               所有者権限で走るため呼び出しロールの権限に依存しない
--   handle_auth_user_signup   : トリガー専用（pg_trigger 登録あり）。RESTから直接呼んでも
--   handle_inquiry_insert       NEW/TG_OP が無く失敗する＝誰にも実行させる必要がない
--
-- 対象外（意図して PUBLIC を残す）
--   verify_login / sync_auth_user_on_login / sync_auth_super_admin_on_login …… ログインに必須
--   get_*_invitation_by_token ×3 / register_*_account ×3 …… 招待リンクに必須
--   get_tenant_plan …… login.html が「ログイン成功後なのに匿名キーのまま」呼んでいる。
--                       先に外すと全テナントのプラン判定が黙って 'standard' に落ちるため、
--                       login.html（共通版・父親版）を直してから別migrationで外す。
--
-- add-only 適合
--   カラム・関数の追加/削除/改名/引数変更は一切しない。権限のみの変更。
--   db-contract のスキーマ形状スナップショット（information_schema.columns + pg_proc署名）は
--   権限を見ないため定義上不変。適用前後の md5 一致で実証する。
--
-- 戻し方（万一画面が壊れた場合・データは一切動かさない）
--   GRANT EXECUTE ON FUNCTION public.<関数名>(<引数型>) TO PUBLIC;

-- ① 既定の PUBLIC を外す
REVOKE EXECUTE ON FUNCTION public.generate_quotation_number(uuid)              FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_my_tax_rates(uuid)                       FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.tax_rate_for(uuid, date, boolean)            FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.handle_auth_user_signup()                    FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.handle_inquiry_insert()                      FROM PUBLIC;

-- ② ログイン済みから呼ぶ3本は明示的に維持（既に付いているが、PUBLIC を外した後も
--    確実に残ることを宣言しておく。冪等）
GRANT EXECUTE ON FUNCTION public.generate_quotation_number(uuid)               TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_tax_rates(uuid)                        TO authenticated;
GRANT EXECUTE ON FUNCTION public.tax_rate_for(uuid, date, boolean)             TO authenticated;

-- ③ authenticated 側は【意図して触らない】
--    トリガー専用2本は authenticated からも外せば更に綺麗になるが、
--    handle_inquiry_insert は**公開お問い合わせフォーム**（Wataの唯一の問い合わせ窓口）の
--    裏で動くトリガー。得られるものが「警告表示が消える」だけに対して、
--    壊れた時の損失が大きすぎるため、必要最小限に留める。
--    （トリガー発火時に EXECUTE 権限は再チェックされない仕様だが、
--      唯一の集客窓口でその仕様に賭ける理由がない）
--    authenticated 側の整理は Advisor 0029 の精査（33本）とまとめて別途行う。
