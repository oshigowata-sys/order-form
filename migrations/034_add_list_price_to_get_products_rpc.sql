-- 034_add_list_price_to_get_products_rpc.sql
-- 注文フォーム（order_form.html）が SECURITY DEFINER RPC `get_products_for_tenant` 経由で
-- 商品マスタを取得しているため、上代統一化に伴い list_price を戻り値に追加する。
-- これにより取引先卸価格未設定時のフォールバック計算（上代 × 掛け率）が正しく動く。

DROP FUNCTION IF EXISTS public.get_products_for_tenant(uuid);

CREATE OR REPLACE FUNCTION public.get_products_for_tenant(p_tenant_id uuid)
RETURNS TABLE (
  id uuid,
  product_code text,
  product_name text,
  price integer,
  list_price integer,
  category text,
  is_food boolean,
  image_url text
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT id, product_code, product_name, price, list_price, category, is_food, image_url
  FROM products
  WHERE tenant_id = p_tenant_id
  ORDER BY category NULLS LAST, product_name;
$$;

GRANT EXECUTE ON FUNCTION public.get_products_for_tenant(uuid) TO anon, authenticated;
