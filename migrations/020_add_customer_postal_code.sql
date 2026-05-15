-- Migration: Add postal_code column to customers table
-- Apply in Supabase Dashboard > SQL Editor.
--
-- 取引先マスタ（customers）に郵便番号カラムを追加。
-- これまで customer.html の郵便番号入力欄は住所自動入力のトリガーとしてしか
-- 使われておらず、DB には保存されていなかった。

ALTER TABLE customers
  ADD COLUMN IF NOT EXISTS postal_code text;

COMMENT ON COLUMN customers.postal_code IS '郵便番号（ハイフン無し7桁推奨。例：0600001）';
