-- Migration: Add wholesale_price column to pricing table
-- Apply in Supabase Dashboard > SQL Editor (or via apply_migration).
--
-- 背景：
-- 父親（実ユーザー）の業務上の思考順は「仕入れいくらだから、これくらいの価格で卸そう
-- → 結果として掛け率何%だった」。掛け率（rate）ではなく卸価格そのものを直接覚えている。
-- 商品マスタの基本単価を変更した際、現状の rate × base_price 方式だと
-- 全取引先の卸価格が連動して変わってしまい業務上の事故になる。
--
-- 対応：
-- 1. pricing.wholesale_price (integer, NULL 許可) を追加
-- 2. 既存レコードを ROUND(products.price * rate) で一括移行
-- 3. RPC get_pricing_for_customer の戻り値に wholesale_price を追加
-- 4. 既存 rate カラムは保持（参考値・後方互換・NULL フォールバック用）

-- ================================================================
-- 1. wholesale_price カラム追加
-- ================================================================
ALTER TABLE pricing
  ADD COLUMN IF NOT EXISTS wholesale_price integer;

COMMENT ON COLUMN pricing.wholesale_price IS
  '取引先別の卸価格（円・整数）。新仕様での主データ。NULL の場合は rate × products.price で計算（後方互換）。';

-- ================================================================
-- 2. 既存レコードの wholesale_price を ROUND(base_price * rate) で初期化
-- ================================================================
UPDATE pricing pr
SET wholesale_price = ROUND(p.price::numeric * pr.rate)::integer
FROM products p
WHERE pr.product_id = p.id
  AND pr.wholesale_price IS NULL
  AND p.price IS NOT NULL
  AND pr.rate IS NOT NULL;

-- ================================================================
-- 3. RPC: get_pricing_for_customer を wholesale_price 込みで再定義
-- ================================================================
-- 戻り値型を変更するため DROP してから CREATE
DROP FUNCTION IF EXISTS public.get_pricing_for_customer(uuid, uuid);

CREATE OR REPLACE FUNCTION public.get_pricing_for_customer(p_tenant_id uuid, p_customer_id uuid)
RETURNS TABLE (
  product_id uuid,
  rate numeric,
  wholesale_price integer
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT product_id, rate, wholesale_price
  FROM pricing
  WHERE tenant_id = p_tenant_id
    AND customer_id = p_customer_id;
$$;

GRANT EXECUTE ON FUNCTION public.get_pricing_for_customer(uuid, uuid) TO anon, authenticated;
