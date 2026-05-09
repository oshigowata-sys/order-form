-- Migration: スーパー管理画面の契約者台帳用カラム追加
-- 適用方法: Supabase Dashboard > SQL Editor に貼り付けて実行

ALTER TABLE tenants
  ADD COLUMN IF NOT EXISTS contact_name text,
  ADD COLUMN IF NOT EXISTS phone text,
  ADD COLUMN IF NOT EXISTS postal_code text,
  ADD COLUMN IF NOT EXISTS address text,
  ADD COLUMN IF NOT EXISTS notes text;

-- 資料DLリードをスーパー管理画面から契約者化・削除できるようにする。
-- 既にポリシーがある環境でも安全に再実行できるようDOブロックで作成する。
ALTER TABLE leads ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'leads' AND policyname = 'leads_super_admin'
  ) THEN
    EXECUTE 'CREATE POLICY "leads_super_admin" ON leads FOR ALL USING (jwt_role() = ''super_admin'') WITH CHECK (jwt_role() = ''super_admin'')';
  END IF;
END $$;
