-- 035_add_remarks_to_order_invoice_items.sql
-- 受注明細・請求書明細に「備考」列を追加（行ごとの自由記述・分配先メモ等）。
-- 既存行は NULL（空表示）。インボイス制度上、既発行請求書のスナップショットは null 維持で改変なし。
-- 2026-05-27 適用済（Supabase MCP apply_migration 経由）。

BEGIN;

ALTER TABLE order_items   ADD COLUMN IF NOT EXISTS remarks text;
ALTER TABLE invoice_items ADD COLUMN IF NOT EXISTS remarks text;

COMMENT ON COLUMN order_items.remarks   IS '行ごと備考（分配先メモ等・自由記述）';
COMMENT ON COLUMN invoice_items.remarks IS '請求書発行時の備考スナップショット（order_items.remarksをコピー）';

COMMIT;
