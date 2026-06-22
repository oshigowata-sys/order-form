-- 053_create_my_order_apply_default_fees.sql
-- 注文フォーム経由の受注作成 RPC（create_my_order）を、取引先マスタの
-- 「いつもの手数料・送料」（migration 052 で追加）を受注に自動コピーするよう更新。
--
-- 背景：
--   create_my_order（migration 046）は orders へ手数料・送料カラムを一切セットせず、
--   フォーム注文は常に手数料0・送料0で保存されていた（納品書に送料が乗らない原因）。
--   本 migration で、ひもづく取引先（customers）の default_*_fee 系の値を
--   受注作成時に orders.handling_fee 等へコピーする。
--
-- 仕様：
--   - シグネチャ・権限・なりすまし対策（tenant/customer を JWT→binding から導出）は 046 のまま不変。
--   - 追加するのは「取引先の既定手数料・送料を orders にコピーする」処理のみ。
--   - コピー後は受注側の値として保存されるため、卸（管理画面の受注編集）で上書き可能。
--   - 既定値が未設定の取引先は 0 / false / 1 のままコピー＝従来どおり手数料・送料なし。
--
-- 後方互換：シグネチャ不変のため CREATE OR REPLACE。既存注文・既発行帳票への遡及なし。

BEGIN;

CREATE OR REPLACE FUNCTION public.create_my_order(
  p_order_code text,
  p_order_date date,
  p_status text,
  p_items jsonb,
  p_input_contact_name text DEFAULT NULL,
  p_tenant_id uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id uuid;
  v_customer_id uuid;
  v_order_id  uuid;
  v_item      jsonb;
  v_idx       int;
  v_bad_count int;
  v_handling_fee        numeric := 0;
  v_shipping_fee        numeric := 0;
  v_handling_fee_charge boolean := false;
  v_shipping_fee_charge boolean := false;
  v_handling_fee_qty    numeric := 1;
  v_shipping_fee_qty    numeric := 1;
BEGIN
  IF (auth.jwt()->'user_metadata'->>'login_id') IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  SELECT b.tenant_id, b.customer_id
    INTO v_tenant_id, v_customer_id
  FROM retail_my_binding(p_tenant_id) b
  LIMIT 1;

  IF v_tenant_id IS NULL OR v_customer_id IS NULL THEN
    RAISE EXCEPTION 'no retail customer bound to this account';
  END IF;

  -- 明細の各 product_id が選択中の卸業者(tenant)所属であることを検証
  SELECT COUNT(*) INTO v_bad_count
  FROM jsonb_array_elements(p_items) AS item
  WHERE NOT EXISTS (
    SELECT 1 FROM products
    WHERE id = (item->>'product_id')::uuid
      AND tenant_id = v_tenant_id
  );
  IF v_bad_count > 0 THEN
    RAISE EXCEPTION 'some products do not belong to tenant %', v_tenant_id;
  END IF;

  -- 取引先マスタの「いつもの手数料・送料」を取得（未設定なら 0 / false / 1）
  SELECT
    COALESCE(default_handling_fee, 0),
    COALESCE(default_shipping_fee, 0),
    COALESCE(default_handling_fee_charge, false),
    COALESCE(default_shipping_fee_charge, false),
    COALESCE(default_handling_fee_qty, 1),
    COALESCE(default_shipping_fee_qty, 1)
  INTO
    v_handling_fee, v_shipping_fee,
    v_handling_fee_charge, v_shipping_fee_charge,
    v_handling_fee_qty, v_shipping_fee_qty
  FROM customers
  WHERE id = v_customer_id;

  INSERT INTO orders (
    tenant_id, customer_id, order_code, order_date, status,
    input_company_name, input_contact_name,
    handling_fee, shipping_fee,
    handling_fee_charge, shipping_fee_charge,
    handling_fee_qty, shipping_fee_qty
  )
  VALUES (
    v_tenant_id, v_customer_id, p_order_code, p_order_date, p_status,
    NULL, p_input_contact_name,
    v_handling_fee, v_shipping_fee,
    v_handling_fee_charge, v_shipping_fee_charge,
    v_handling_fee_qty, v_shipping_fee_qty
  )
  RETURNING id INTO v_order_id;

  FOR v_item, v_idx IN
    SELECT t.elem, (t.ord - 1)::int
    FROM jsonb_array_elements(p_items) WITH ORDINALITY AS t(elem, ord)
  LOOP
    INSERT INTO order_items (order_id, product_id, quantity, unit_price, display_order)
    VALUES (
      v_order_id,
      (v_item->>'product_id')::uuid,
      (v_item->>'quantity')::int,
      (v_item->>'unit_price')::int,
      v_idx
    );
  END LOOP;

  RETURN v_order_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_my_order(text, date, text, jsonb, text, uuid) TO authenticated;

COMMIT;
