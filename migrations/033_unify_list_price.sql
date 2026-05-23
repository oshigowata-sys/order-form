-- 033_unify_list_price.sql
-- 商品マスタの「基本単価（price）」と「上代（list_price）」を統一する。
-- 業務的に「1商品＝1つの定価（上代）」に揃え、画面入力からは基本単価を廃止する。
-- products.price カラムは過去スナップショット互換・後方互換のため残し、保存時に price = list_price で常時同期させる。
--
-- このマイグレーションでは、既存データを両方向に補完する。
--   1) list_price が NULL/0 の行 → price を list_price にコピー（demo の12件など）
--   2) price が NULL/0 の行     → list_price を price にコピー（jobs-test の8件など）
--   3) 両方とも値が入っているが食い違う行 → 触らない（list_price を優先表示するため、price はスナップショット互換用にそのまま）

BEGIN;

-- 1) 上代が空の行：基本単価の値を上代にコピー
UPDATE products
SET list_price = price
WHERE (list_price IS NULL OR list_price = 0)
  AND price IS NOT NULL
  AND price > 0;

-- 2) 基本単価が空の行：上代の値を基本単価にコピー
UPDATE products
SET price = list_price
WHERE (price IS NULL OR price = 0)
  AND list_price IS NOT NULL
  AND list_price > 0;

COMMIT;
