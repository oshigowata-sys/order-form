-- Migration 037: 請求書の発行取り消し（取消済マーク）対応
-- Purpose:
--   発行済み請求書を「取消済」状態にして、明細・本体は残しつつ
--   同期間で再発行できるようにする機能のためのカラム追加。
--
--   既存の superseded_at は「同期間で別の請求書が発行されて旧版になった
--   （上書き）」用途で使われているため、明示的な「発行取り消し」用に
--   cancelled_at を分離する。
--
-- 運用ルール（フロント側で実装）:
--   - 発行済み行に「発行取り消し」ボタン → cancelled_at = now() をセット
--   - 取消済の請求書は一覧で「取消済」表示
--   - 重複ブロックロジックは superseded_at IS NULL AND cancelled_at IS NULL を有効条件に
--   - 過去請求書探索（初回判定・前回請求額参照）も取消済を除外
--   - 取消済の請求書PDFは引き続き表示可能（証跡）
--   - 取消済の請求書は完全削除も可能（別ボタンで物理削除）
--
-- 既存データへの影響:
--   - 全件 cancelled_at=NULL（有効）でデフォルト
--   - 一覧表示・PDF表示はこれまで通り
--   - 既発行分は取消済として扱われない

ALTER TABLE invoices
  ADD COLUMN IF NOT EXISTS cancelled_at TIMESTAMPTZ;

-- 有効レコード索引を取消済も除外する形に張り替え
DROP INDEX IF EXISTS invoices_active_by_period_idx;
CREATE INDEX IF NOT EXISTS invoices_active_by_period_idx
  ON invoices (tenant_id, customer_id, period_start, period_end)
  WHERE superseded_at IS NULL AND cancelled_at IS NULL;

COMMENT ON COLUMN invoices.cancelled_at IS
  '発行取り消し日時。NULL=有効、値あり=取消済（明細は残すが業務上は無効扱い）';
