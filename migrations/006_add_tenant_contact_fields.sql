-- Migration: スーパー管理画面の契約者台帳用カラム追加
-- 適用方法: Supabase Dashboard > SQL Editor に貼り付けて実行

ALTER TABLE tenants
  ADD COLUMN IF NOT EXISTS contact_name text,
  ADD COLUMN IF NOT EXISTS phone text,
  ADD COLUMN IF NOT EXISTS postal_code text,
  ADD COLUMN IF NOT EXISTS address text,
  ADD COLUMN IF NOT EXISTS notes text;

