-- 038_add_notes_remarks_for_invoice_order_quotation.sql
-- 帳票全体の「フリー備考欄」と見積書明細の「行ごと備考」を追加。
--
-- 1) orders.notes
--    受注（納品書ベース）の帳票全体に表示するフリー備考。
--    受注編集画面の textarea で編集・保存し、納品書PDFのフッターに表示。
--
-- 2) invoices.notes
--    請求書発行時に表示するフリー備考。発行画面で編集し、請求書PDFのフッターに表示。
--    発行済み請求書も編集可（インボイス制度上の改変対象は金額・税率等で、メモは対象外）。
--
-- 3) quotation_items.remarks
--    見積書明細の行ごと備考。order_items.remarks / invoice_items.remarks と同パターン（PR #257）。
--
-- 既存：
--   - quotations.notes は migration 019 で追加済み（再利用するため本ファイルでは追加しない）
--   - order_items.remarks / invoice_items.remarks は migration 035 で追加済み
--
-- 既存行は NULL（空表示）。インボイス制度上の影響なし。

BEGIN;

ALTER TABLE orders          ADD COLUMN IF NOT EXISTS notes   text;
ALTER TABLE invoices        ADD COLUMN IF NOT EXISTS notes   text;
ALTER TABLE quotation_items ADD COLUMN IF NOT EXISTS remarks text;

COMMENT ON COLUMN orders.notes          IS '帳票全体のフリー備考（納品書PDFフッターに表示）';
COMMENT ON COLUMN invoices.notes        IS '請求書発行時のフリー備考（請求書PDFフッターに表示）';
COMMENT ON COLUMN quotation_items.remarks IS '見積書明細の行ごと備考（自由記述・分配先メモ等）';

COMMIT;
