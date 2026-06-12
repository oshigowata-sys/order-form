-- Migration 040: order_items に display_order（明細の入力順）を追加
--
-- 背景:
--   受注一覧の新規受注・受注編集では明細行を並列POST（Promise.all）で保存しており、
--   DBへの到着順が入力順と一致しない。さらに取得側（受注詳細・納品書・請求書PDF）も
--   ORDER BY 指定なしで明細を読むため、帳票の明細順が入力順とズレる。
--
-- 対応:
--   1) order_items.display_order を追加（既存行は 0 のまま）
--   2) 取得用の (order_id, display_order) 索引を追加
--   3) 注文フォーム（anon）用 create_anon_order RPC も入力順を記録するよう再作成
--      （引数構成・テナント検証ロジックは 026 のまま維持）
--
-- 既存データへの影響:
--   既存明細の本来の入力順は記録が存在せず復元不能のため backfill しない（全行 0）。
--   既発行請求書の invoice_items スナップショットは一切改変しない（インボイス制度）。

ALTER TABLE order_items ADD COLUMN IF NOT EXISTS display_order integer NOT NULL DEFAULT 0;

COMMENT ON COLUMN order_items.display_order IS '明細の入力順（0始まり）。受注詳細・納品書・請求書の表示順に使用';

CREATE INDEX IF NOT EXISTS order_items_order_display_idx
  ON order_items (order_id, display_order);

-- ================================================================
-- create_anon_order: 明細 INSERT 時に display_order を採番
-- （migration 026 の定義をベースに、display_order 追加のみ）
-- ================================================================
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
  v_idx      int;
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

  -- WITH ORDINALITY で配列の並び順（＝カートの入力順）を display_order に記録
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
$function$;

GRANT EXECUTE ON FUNCTION public.create_anon_order(uuid, uuid, text, date, text, jsonb, text, text) TO anon, authenticated;
