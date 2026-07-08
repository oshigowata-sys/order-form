-- 059: settings にメール通知の設定2項目を追加
-- 新規注文のメール通知（第2弾）用。ON/OFFスイッチ（初期OFF＝非常停止兼用）と通知先アドレス。
-- add-only：既存カラム・関数には一切触れない。互換チェック[OK]（2026-07-08）。
--
-- 2026-07-08 実行（Supabase apply_migration 名は「058_add_notify_email_settings」＝
-- 適用時に通し番号を誤って058と付けた。DB上の名前は変更不可のためそのまま。正しい通し番号はこの059）。
-- 画面側の対応：共通版 PR #407（settings.html 設定カード／orders.html・shop.html 投げっぱなし呼び出し／Edge Function notify-new-order）。

ALTER TABLE public.settings
  ADD COLUMN IF NOT EXISTS notify_email_enabled boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS notify_emails jsonb DEFAULT '[]'::jsonb;

COMMENT ON COLUMN public.settings.notify_email_enabled IS '新規注文のメール通知ON/OFF（初期OFF・非常停止スイッチ兼用）';
COMMENT ON COLUMN public.settings.notify_emails IS '通知先メールアドレスの配列（複数登録可）';
