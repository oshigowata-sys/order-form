-- 056: 未使用の診断用関数を削除（攻撃面の縮小）
--
-- 背景：
--   diagnose_invited_account_registration は招待登録(register_invited_account)の
--   不具合調査用に開発初期(010)で作成したデバッグ用関数。本番運用では未使用。
--   - 共通版/父親版どちらのフロントコードからも参照ゼロ
--   - DB内の他関数からの呼び出しもゼロ
--   - それにも関わらず anon(匿名) に EXECUTE 権限が付いたまま残存していた
--     （p_password まで受け取る診断のため、放置は小さな情報漏れ面になりうる）
--   048 のコメントでも「本番不要の診断用デッドコード・削除候補」と明記済み。
--
-- 本体の register_invited_account は現役のため残す（これは削除しない）。
-- add-only 原則の例外＝「使われていないデッドコードの除去」。後方互換影響なし。
--
-- 2026-06-30 実行（Supabase apply_migration: drop_dead_diagnose_invited_function）。

DROP FUNCTION IF EXISTS public.diagnose_invited_account_registration(text, text, text, text);
