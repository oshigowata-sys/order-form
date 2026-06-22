-- 054_fix_leads_rls_super_admin.sql
-- 資料DLリード（leads）のRLSを、問い合わせ（inquiries）と同じ super_admin モデルに統一する。
--
-- 背景・問題：
--   leads には super_admin 用のポリシーが無く、ポリシーは
--     ・anon_insert_leads（anon INSERT）
--     ・authenticated_select_leads（authenticated に SELECT・条件 true ＝全行公開）
--   の2つだけだった。これにより：
--   【問題1：バグ】DELETE/UPDATE を許すポリシーが皆無 → スーパー管理画面（super_admin）からの
--     リード削除が「0行削除＝成功」で握りつぶされ、削除ボタンが効かない。
--     createTenantFromLead（契約者化）の削除も同様に効かず、リードが残り続けていた。
--   【問題2：情報露出】SELECT が authenticated 全体に open（qual=true）。ログインユーザーなら
--     誰でも（小売店 retail アカウント等を含む）全リード（見込み客の社名・氏名・メール）を読めた。
--
-- 是正：inquiries（inquiries_super_admin = FOR ALL USING jwt_role()='super_admin'）と同型に統一。
--   ・authenticated_select_leads（過剰な公開SELECT）を撤去
--   ・leads_super_admin（FOR ALL・super_admin限定）を新設 → SELECT/UPDATE/DELETE を運営者に許可
--   ・anon_insert_leads（公開資料DLフォームからの登録）は温存（撤去しない）
--
-- 影響：leads を読むのはスーパー管理画面（super_admin）のみ・書くのは公開フォーム（anon）のみ。
--   一般 authenticated が leads を読む正規の用途は存在しないため、締めても機能退行なし。

BEGIN;

DROP POLICY IF EXISTS authenticated_select_leads ON leads;

CREATE POLICY leads_super_admin ON leads
  FOR ALL
  USING (jwt_role() = 'super_admin');

COMMIT;
