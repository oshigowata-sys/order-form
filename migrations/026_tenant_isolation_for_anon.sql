-- Migration: Tenant isolation for anon order form access
-- Apply in Supabase Dashboard > SQL Editor.
--
-- 注文フォーム（order_form.html）はログイン不要設計だが、anon の products / pricing
-- 直接 SELECT 許可が qual='true' で全テナント参照可能だった。
-- URLの tenant パラメータを差し替えれば他テナントの商品マスタ・取引先別掛け率（値引率）
-- まで見える脆弱性。
--
-- 対応：
-- 1. anon は専用 RPC でしか商品・掛け率を取得できない
-- 2. RPC 側で「指定された tenant の範囲だけ」を返す
-- 3. 注文登録 RPC でも「明細の product_id / customer_id がテナント所属」を検証

CREATE SCHEMA IF NOT EXISTS extensions;

-- ================================================================
-- 1. 商品取得 RPC（テナント分離）
-- ================================================================
CREATE OR REPLACE FUNCTION public.get_products_for_tenant(p_tenant_id uuid)
RETURNS TABLE (
  id uuid,
  product_code text,
  product_name text,
  price integer,
  category text,
  is_food boolean,
  image_url text
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT id, product_code, product_name, price, category, is_food, image_url
  FROM products
  WHERE tenant_id = p_tenant_id
  ORDER BY category NULLS LAST, product_name;
$$;

GRANT EXECUTE ON FUNCTION public.get_products_for_tenant(uuid) TO anon, authenticated;

-- ================================================================
-- 2. 掛け率取得 RPC（テナント + 取引先 分離）
-- ================================================================
CREATE OR REPLACE FUNCTION public.get_pricing_for_customer(p_tenant_id uuid, p_customer_id uuid)
RETURNS TABLE (
  product_id uuid,
  rate numeric
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT product_id, rate
  FROM pricing
  WHERE tenant_id = p_tenant_id
    AND customer_id = p_customer_id;
$$;

GRANT EXECUTE ON FUNCTION public.get_pricing_for_customer(uuid, uuid) TO anon, authenticated;

-- ================================================================
-- 3. 注文登録 RPC を強化（テナント検証追加）
-- ================================================================
-- 既存定義を DROP して新定義で再作成（引数構成は維持・内部に検証ロジック追加）
DROP FUNCTION IF EXISTS public.create_anon_order(uuid, uuid, text, date, text, jsonb, text, text);

CREATE OR REPLACE FUNCTION public.create_anon_order(
  p_tenant_id uuid,
  p_customer_id uuid,
  p_order_code text,
  p_order_date date,
  p_status text,
  p_items jsonb,
  p_input_company_name text DEFAULT NULL,
  p_input_contact_name text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_order_id uuid;
  v_item     jsonb;
  v_cust_tid uuid;
  v_bad_count int;
BEGIN
  IF p_tenant_id IS NULL THEN
    RAISE EXCEPTION 'tenant_id is required';
  END IF;

  -- 取引先IDが指定された場合、そのテナント所属を検証
  IF p_customer_id IS NOT NULL THEN
    SELECT tenant_id INTO v_cust_tid FROM customers WHERE id = p_customer_id;
    IF v_cust_tid IS NULL OR v_cust_tid <> p_tenant_id THEN
      RAISE EXCEPTION 'customer % does not belong to tenant %', p_customer_id, p_tenant_id;
    END IF;
  END IF;

  -- 明細の各 product_id がテナント所属であることを検証
  SELECT COUNT(*) INTO v_bad_count
  FROM jsonb_array_elements(p_items) AS item
  WHERE NOT EXISTS (
    SELECT 1 FROM products
    WHERE id = (item->>'product_id')::uuid
      AND tenant_id = p_tenant_id
  );
  IF v_bad_count > 0 THEN
    RAISE EXCEPTION 'some products do not belong to tenant %', p_tenant_id;
  END IF;

  INSERT INTO orders (
    tenant_id, customer_id, order_code, order_date, status,
    input_company_name, input_contact_name
  )
  VALUES (
    p_tenant_id, p_customer_id, p_order_code, p_order_date, p_status,
    p_input_company_name, p_input_contact_name
  )
  RETURNING id INTO v_order_id;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    INSERT INTO order_items (order_id, product_id, quantity, unit_price)
    VALUES (
      v_order_id,
      (v_item->>'product_id')::uuid,
      (v_item->>'quantity')::int,
      (v_item->>'unit_price')::int
    );
  END LOOP;

  RETURN v_order_id;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.create_anon_order(uuid, uuid, text, date, text, jsonb, text, text) TO anon, authenticated;

-- ================================================================
-- 4. anon の products / pricing への直接 SELECT 権限を剥奪
-- ================================================================
-- authenticated 用の products_tenant_all / pricing_tenant_all は残るので、
-- ログイン済みユーザーの管理画面は影響なし。
DROP POLICY IF EXISTS "products_anon_select" ON products;
DROP POLICY IF EXISTS "pricing_anon_select"  ON pricing;
