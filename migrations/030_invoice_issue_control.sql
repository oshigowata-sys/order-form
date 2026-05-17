-- Migration 030: 請求書の途中発行・本発行・上書き制御
-- Purpose:
--   現状は「途中発行」ボタンを押すたびに同期間の請求書が複数件できてしまう。
--   業務上は月1件運用が望ましいので、以下のフラグを追加して制御する：
--   - is_interim: true = 途中発行、 false = 本発行（月末締めの正式発行）
--   - superseded_at: 上書きされた日時。NULL なら有効レコード
--
-- 運用ルール（フロント側で実装）:
--   - 途中発行 → 同期間に有効な本発行があればブロック、有効な途中発行があれば
--     superseded_at をセットして上書き
--   - 本発行 → 同期間に有効な本発行があればブロック、有効な途中発行があれば
--     superseded_at をセットして上書き
--
-- 既存データへの影響:
--   - 全件 is_interim=false（本発行扱い）でデフォルト
--   - superseded_at は全件 NULL（有効）のまま
--   - 一覧表示はこれまで通り
--   - すでにテスト発行で重複している既存レコードは残るが、新規発行時に
--     重複ブロック / 上書きが動くようになる

ALTER TABLE invoices
  ADD COLUMN IF NOT EXISTS is_interim BOOLEAN NOT NULL DEFAULT false;

ALTER TABLE invoices
  ADD COLUMN IF NOT EXISTS superseded_at TIMESTAMPTZ;

-- 有効レコード（superseded_at IS NULL）の高速検索インデックス
CREATE INDEX IF NOT EXISTS invoices_active_by_period_idx
  ON invoices (tenant_id, customer_id, period_start, period_end)
  WHERE superseded_at IS NULL;
