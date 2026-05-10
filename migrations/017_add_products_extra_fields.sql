-- =====================================================
-- Migration 017: products テーブル拡張
-- =====================================================
-- 目的: 商品マスタに「上代」「仕入価格」「ケース入数」「JANコード」を追加
--   - list_price    : 上代（メーカー希望小売価格／定価）
--   - cost_price    : 仕入価格（原価）
--   - case_quantity : ケース入数（1ケースあたりの個数。バラ売りは1）
--   - jan_code      : JANコード（8桁または13桁の数字）
--
-- 既存の products.price（基本単価）は卸売の「下代」相当としてそのまま残す。
-- =====================================================

ALTER TABLE products
  ADD COLUMN IF NOT EXISTS list_price integer,
  ADD COLUMN IF NOT EXISTS cost_price integer,
  ADD COLUMN IF NOT EXISTS case_quantity integer DEFAULT 1,
  ADD COLUMN IF NOT EXISTS jan_code text;

-- JANコードのテナント内ユニーク制約（NULL以外。同一テナントでJAN重複登録を防止）
CREATE UNIQUE INDEX IF NOT EXISTS idx_products_tenant_jan_code_unique
  ON products (tenant_id, jan_code)
  WHERE jan_code IS NOT NULL;

-- JANコード形式チェック（NULL or 8桁数字 or 13桁数字）
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_products_jan_code_format'
  ) THEN
    ALTER TABLE products
      ADD CONSTRAINT chk_products_jan_code_format
      CHECK (jan_code IS NULL OR jan_code ~ '^[0-9]{8}$' OR jan_code ~ '^[0-9]{13}$');
  END IF;
END $$;

COMMENT ON COLUMN products.list_price     IS '上代（メーカー希望小売価格／定価）';
COMMENT ON COLUMN products.cost_price     IS '仕入価格（原価）';
COMMENT ON COLUMN products.case_quantity  IS 'ケース入数（1ケースあたりの個数。バラ売りは1）';
COMMENT ON COLUMN products.jan_code       IS 'JANコード（8桁または13桁の数字）';
