-- Migration: Add quotation expiry type
-- Apply in Supabase Dashboard > SQL Editor.
--
-- 有効期限を「次回見積まで」または「日付指定」から選べるようにする。
-- expiry_date は既存の NOT NULL 制約を維持し、next_quote の場合は画面上は日付を出さない。

ALTER TABLE quotations
  ADD COLUMN IF NOT EXISTS expiry_type text NOT NULL DEFAULT 'next_quote';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_quotations_expiry_type'
  ) THEN
    ALTER TABLE quotations
      ADD CONSTRAINT chk_quotations_expiry_type
      CHECK (expiry_type IN ('next_quote', 'date'));
  END IF;
END $$;

COMMENT ON COLUMN quotations.expiry_type IS '見積書の有効期限種別（next_quote=次回見積まで、date=日付指定）';
