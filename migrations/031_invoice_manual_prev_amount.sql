-- Migration 031: 請求書に「手入力した前回請求額」カラムを追加
-- Purpose:
--   MeguRee 導入時の初回請求書は過去データがないため「前回請求額」が
--   自動取得できない。初回請求書発行時にユーザーがポップアップで
--   入力した値を保存するためのカラムを追加する。
--
-- 運用ルール（フロント側で実装）:
--   - 初回判定: その取引先の有効な請求書（superseded_at IS NULL）が0件
--   - 初回ならポップアップ表示 → 入力値を invoices.manual_prev_amount に保存
--   - 翌月以降は通常通り前月請求書（total_incl_tax）から自動取得
--   - 修正したい時はその初回請求書を開いて編集（rectify は invoice.html 側）
--
-- 既存データへの影響:
--   - 全件 manual_prev_amount=NULL でデフォルト
--   - 表示・計算ロジックには影響なし（NULL なら従来通り前月から取得）

ALTER TABLE invoices
  ADD COLUMN IF NOT EXISTS manual_prev_amount INTEGER;

COMMENT ON COLUMN invoices.manual_prev_amount IS
  'MeguRee 導入時の初回請求書で、ユーザーが手入力した前回請求額。NULL なら未入力（または前月請求書から自動取得）';
