-- Migration: Extend quotation_items with list_price / case_quantity / jan_code
-- Apply in Supabase Dashboard > SQL Editor.
--
-- 見積書フォーマットを「上代・商品名・入数・数量・卸価格・金額・JANコード」の
-- 7列構成に刷新するため、明細に商品マスタからのスナップショット列を追加。

ALTER TABLE quotation_items
  ADD COLUMN IF NOT EXISTS list_price integer,
  ADD COLUMN IF NOT EXISTS case_quantity integer DEFAULT 1,
  ADD COLUMN IF NOT EXISTS jan_code text;

COMMENT ON COLUMN quotation_items.list_price    IS '上代（発行時点の products.list_price スナップショット）';
COMMENT ON COLUMN quotation_items.case_quantity IS 'ケース入数（発行時点の products.case_quantity スナップショット）';
COMMENT ON COLUMN quotation_items.jan_code      IS 'JANコード（発行時点の products.jan_code スナップショット）';
