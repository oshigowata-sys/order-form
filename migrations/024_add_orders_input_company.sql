-- Migration: Add input_company_name / input_contact_name to orders and extend create_anon_order
-- Apply in Supabase Dashboard > SQL Editor.
--
-- 注文フォーム（order_form.html）でログイン不要・取引先IDなしの「フリー入力客」が
-- 会社名・担当者名を入力した場合、その入力値が orders にもどこにも残らない問題への対処。
-- customer_id への紐付けに失敗しても「誰からの注文か」を画面で追跡できるようにする。

ALTER TABLE orders
  ADD COLUMN IF NOT EXISTS input_company_name text,
  ADD COLUMN IF NOT EXISTS input_contact_name text;

COMMENT ON COLUMN orders.input_company_name IS 'free-form input company name from order_form.html (kept for traceability when customer_id is null)';
COMMENT ON COLUMN orders.input_contact_name IS 'free-form input contact name from order_form.html';

-- ================================================================
-- create_anon_order RPC を新引数 2 つ追加で再作成
-- 既存呼び出しは DEFAULT NULL で動き、新規呼び出しは追加引数も渡す。
-- ================================================================
DROP FUNCTION IF EXISTS public.create_anon_order(uuid, uuid, text, date, text, jsonb);

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
BEGIN
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
