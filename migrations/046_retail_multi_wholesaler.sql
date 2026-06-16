-- Migration 046: 小売店「1ログインで複数卸業者」対応
-- 適用方法: Supabase MCP apply_migration もしくは Dashboard > SQL Editor
--
-- 目的:
--   1つの retail ログイン（login_id＝メール）が、複数の卸業者(tenant)の取引先(customer)
--   として注文できるようにする。業界標準（インフォマート「取引先切替」/ CO-NECT）に倣い、
--   ログイン後にヘッダーで卸業者を切り替える形にする。
--
-- 設計の肝（041/043 の方針を踏襲）:
--   (1) 身元は accounts（login_id）のまま。1ログイン ↔ 複数(tenant,customer) を
--       新テーブル retail_memberships でひもづける。
--   (2) なりすまし排除は不変：customer/tenant はクライアントから受け取らず、
--       JWT(login_id) と retail_memberships から導出する。
--   (3) retail の JWT に tenant_id クレームを載せない方針は不変（他テナント不可視）。
--
-- 後方互換（厳守・CLAUDE.md 不変ルール）:
--   すべて追加のみ。既存列・既存関数の引数の削除/改名なし。
--   既存 retail RPC には p_tenant_id uuid DEFAULT NULL を「末尾に追加」するだけ。
--   p_tenant_id IS NULL のときは従来通り accounts から導出（旧クライアントも壊れない）。
--   accounts.tenant_id / customer_id 列は残す。

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ================================================================
-- 1. ひもづけテーブル（1ログイン ↔ 複数(tenant,customer)）
--    RLS は付けず、SECURITY DEFINER RPC 経由でのみ読み書きする（既存 retail RPC と同方針）。
-- ================================================================
CREATE TABLE IF NOT EXISTS public.retail_memberships (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  login_id    text NOT NULL,
  tenant_id   uuid NOT NULL,
  customer_id uuid NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (login_id, tenant_id)
);

CREATE INDEX IF NOT EXISTS retail_memberships_login_idx
  ON public.retail_memberships (login_id);
CREATE INDEX IF NOT EXISTS retail_memberships_tenant_customer_idx
  ON public.retail_memberships (tenant_id, customer_id);

COMMENT ON TABLE public.retail_memberships IS
  '小売店ログイン(login_id) と 卸業者(tenant_id)×取引先(customer_id) のひもづけ。1ログインで複数卸業者対応';

-- ================================================================
-- 2. 既存 retail アカウントを membership に複製移行（冪等）
-- ================================================================
INSERT INTO public.retail_memberships (login_id, tenant_id, customer_id)
SELECT a.login_id, a.tenant_id, a.customer_id
FROM accounts a
WHERE a.role = 'retail'
  AND a.tenant_id IS NOT NULL
  AND a.customer_id IS NOT NULL
ON CONFLICT (login_id, tenant_id) DO NOTHING;

-- ================================================================
-- 3. 内部ヘルパー：JWT(login_id) + p_tenant_id から自分の (tenant,customer) を導出
--    p_tenant_id IS NULL → 従来通り accounts から（単一ひもづけ・旧挙動）
--    p_tenant_id 指定    → retail_memberships で本人所有を検証して導出
--    どちらも該当しなければ 0 行（呼び出し側で「該当なし」として扱う）
-- ================================================================
CREATE OR REPLACE FUNCTION public.retail_my_binding(p_tenant_id uuid DEFAULT NULL)
RETURNS TABLE(tenant_id uuid, customer_id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_login text := auth.jwt()->'user_metadata'->>'login_id';
BEGIN
  IF p_tenant_id IS NULL THEN
    -- 旧挙動：単一ひもづけを accounts から導出
    RETURN QUERY
      SELECT a.tenant_id, a.customer_id
      FROM accounts a
      WHERE a.login_id = v_login AND a.role = 'retail'
      LIMIT 1;
  ELSE
    -- 指定卸業者の membership を本人所有検証して導出
    RETURN QUERY
      SELECT m.tenant_id, m.customer_id
      FROM retail_memberships m
      WHERE m.login_id = v_login AND m.tenant_id = p_tenant_id
      LIMIT 1;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.retail_my_binding(uuid) TO authenticated;

-- ================================================================
-- 4. 切替UI用：自分がひもづいている卸業者・取引先の一覧
-- ================================================================
CREATE OR REPLACE FUNCTION public.get_my_memberships()
RETURNS TABLE(tenant_id uuid, customer_id uuid, company_name text, wholesaler_name text)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT m.tenant_id, m.customer_id, c.company_name, s.company_name AS wholesaler_name
  FROM retail_memberships m
  JOIN customers c   ON c.id = m.customer_id
  LEFT JOIN settings s ON s.tenant_id = m.tenant_id
  WHERE m.login_id = (auth.jwt()->'user_metadata'->>'login_id')
  ORDER BY s.company_name NULLS LAST, c.company_name;
$$;

GRANT EXECUTE ON FUNCTION public.get_my_memberships() TO authenticated;

-- ================================================================
-- 5. ログイン中の retail が招待トークンの(tenant,customer)を自分に追加
--    （卸業者Bが同じ小売店を招待 → 既存ログインに追加でひもづけ）
--    トークン検証条件は register_retail_account と同一。
-- ================================================================
CREATE OR REPLACE FUNCTION public.link_retail_membership(p_token text)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_login text := auth.jwt()->'user_metadata'->>'login_id';
  v_role  text;
  v_inv   invitations%rowtype;
  v_wholesaler text;
BEGIN
  IF v_login IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_authenticated');
  END IF;

  SELECT role INTO v_role FROM accounts WHERE login_id = v_login;
  IF v_role IS DISTINCT FROM 'retail' THEN
    RETURN json_build_object('success', false, 'error', 'not_retail');
  END IF;

  SELECT * INTO v_inv
  FROM invitations
  WHERE token = p_token
    AND used_at IS NULL
    AND expires_at > now()
    AND intended_role = 'retail'
  LIMIT 1
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'invalid_or_expired');
  END IF;

  INSERT INTO retail_memberships (login_id, tenant_id, customer_id)
  VALUES (v_login, v_inv.tenant_id, v_inv.customer_id)
  ON CONFLICT (login_id, tenant_id) DO NOTHING;

  UPDATE invitations SET used_at = now() WHERE id = v_inv.id;

  SELECT company_name INTO v_wholesaler FROM settings WHERE tenant_id = v_inv.tenant_id;

  RETURN json_build_object('success', true,
                           'tenant_id', v_inv.tenant_id,
                           'wholesaler_name', v_wholesaler);
END;
$$;

GRANT EXECUTE ON FUNCTION public.link_retail_membership(text) TO authenticated;

-- ================================================================
-- 6. 既存 retail RPC を p_tenant_id 対応に置換
--    省略可能引数(DEFAULT NULL)を足すため、旧シグネチャを先に DROP してから作り直す。
--    （引数なし版と (uuid DEFAULT NULL) 版が共存すると呼び出しが曖昧になるため。
--      migration 041 の verify_login と同じ「DROP→再作成」手法。
--      旧呼び出し＝引数なし/5引数は、新版を DEFAULT NULL で呼ぶ形になり挙動は維持される＝後方互換）
-- ================================================================
DROP FUNCTION IF EXISTS public.get_my_customer();
DROP FUNCTION IF EXISTS public.get_my_products();
DROP FUNCTION IF EXISTS public.get_my_pricing();
DROP FUNCTION IF EXISTS public.get_my_orders();
DROP FUNCTION IF EXISTS public.create_my_order(text, date, text, jsonb, text);

-- 6-1. 自分の取引先
CREATE OR REPLACE FUNCTION public.get_my_customer(p_tenant_id uuid DEFAULT NULL)
RETURNS TABLE(customer_id uuid, company_name text)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT b.customer_id, c.company_name
  FROM retail_my_binding(p_tenant_id) b
  JOIN customers c ON c.id = b.customer_id
  LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION public.get_my_customer(uuid) TO authenticated;

-- 6-2. 自分の商品（その卸業者の商品）
CREATE OR REPLACE FUNCTION public.get_my_products(p_tenant_id uuid DEFAULT NULL)
RETURNS TABLE(id uuid, product_code text, product_name text, price integer, list_price integer, category text, is_food boolean, image_url text)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT p.id, p.product_code, p.product_name, p.price, p.list_price, p.category, p.is_food, p.image_url
  FROM products p
  WHERE p.tenant_id = (SELECT b.tenant_id FROM retail_my_binding(p_tenant_id) b LIMIT 1)
  ORDER BY p.category NULLS LAST, p.product_name;
$$;

GRANT EXECUTE ON FUNCTION public.get_my_products(uuid) TO authenticated;

-- 6-3. 自分の卸価格
CREATE OR REPLACE FUNCTION public.get_my_pricing(p_tenant_id uuid DEFAULT NULL)
RETURNS TABLE(product_id uuid, rate numeric, wholesale_price integer)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT pr.product_id, pr.rate, pr.wholesale_price
  FROM pricing pr
  JOIN retail_my_binding(p_tenant_id) b
    ON pr.tenant_id = b.tenant_id
   AND pr.customer_id = b.customer_id;
$$;

GRANT EXECUTE ON FUNCTION public.get_my_pricing(uuid) TO authenticated;

-- 6-4. 自分の注文一覧
CREATE OR REPLACE FUNCTION public.get_my_orders(p_tenant_id uuid DEFAULT NULL)
RETURNS TABLE(order_id uuid, order_code text, order_date date, status text,
              item_count int, subtotal bigint, total bigint)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  WITH me AS (
    SELECT b.tenant_id, b.customer_id FROM retail_my_binding(p_tenant_id) b LIMIT 1
  )
  SELECT
    o.id, o.order_code, o.order_date, o.status,
    (SELECT count(*) FROM order_items oi WHERE oi.order_id = o.id)::int,
    COALESCE((SELECT sum(oi.unit_price * oi.quantity)
              FROM order_items oi WHERE oi.order_id = o.id), 0)::bigint,
    COALESCE((SELECT sum(oi.unit_price * oi.quantity
                     + round(oi.unit_price * oi.quantity *
                             (CASE WHEN p.is_food THEN 0.08 ELSE 0.10 END)))
              FROM order_items oi JOIN products p ON p.id = oi.product_id
              WHERE oi.order_id = o.id), 0)::bigint
  FROM orders o, me
  WHERE o.tenant_id = me.tenant_id
    AND o.customer_id = me.customer_id
  ORDER BY o.order_date DESC, o.created_at DESC;
$$;

GRANT EXECUTE ON FUNCTION public.get_my_orders(uuid) TO authenticated;

-- 6-5. 注文明細（所有検証：注文の(tenant,customer)が自分の membership 集合に含まれるか）
--      引数は不変（p_order_id のみ）。複数卸業者でも自分の注文だけ見える。
CREATE OR REPLACE FUNCTION public.get_my_order_detail(p_order_id uuid)
RETURNS TABLE(product_id uuid, product_name text, quantity int, unit_price int,
              is_food boolean, display_order int)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT oi.product_id, p.product_name, oi.quantity, oi.unit_price, p.is_food, oi.display_order
  FROM order_items oi
  JOIN orders o   ON o.id = oi.order_id
  JOIN products p ON p.id = oi.product_id
  WHERE oi.order_id = p_order_id
    AND EXISTS (
      SELECT 1 FROM retail_memberships m
      WHERE m.login_id = (auth.jwt()->'user_metadata'->>'login_id')
        AND m.tenant_id = o.tenant_id
        AND m.customer_id = o.customer_id
    )
  ORDER BY oi.display_order;
$$;

GRANT EXECUTE ON FUNCTION public.get_my_order_detail(uuid) TO authenticated;

-- 6-6. 認証版の注文登録（p_tenant_id 末尾追加・他は不変）
--      tenant/customer はクライアント値を信用せず retail_my_binding から導出。
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

  INSERT INTO orders (
    tenant_id, customer_id, order_code, order_date, status,
    input_company_name, input_contact_name
  )
  VALUES (
    v_tenant_id, v_customer_id, p_order_code, p_order_date, p_status,
    NULL, p_input_contact_name
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

-- ================================================================
-- 7. register_retail_account を membership 同時作成に拡張
--    （新規登録時に accounts と retail_memberships の両方へ書く）
-- ================================================================
CREATE OR REPLACE FUNCTION public.register_retail_account(
  p_token text,
  p_login_id text,
  p_password text,
  p_terms_version text DEFAULT NULL,
  p_privacy_version text DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions  -- crypt/gen_salt は extensions スキーマ（migration 042 の修正を維持）
AS $$
DECLARE
  v_inv  invitations%rowtype;
  v_name text;
BEGIN
  IF p_token IS NULL OR length(trim(p_token)) = 0 THEN
    RETURN json_build_object('success', false, 'error', 'invalid_token');
  END IF;
  IF p_login_id IS NULL OR length(trim(p_login_id)) = 0 THEN
    RETURN json_build_object('success', false, 'error', 'login_required');
  END IF;
  IF p_password IS NULL OR length(p_password) < 6 THEN
    RETURN json_build_object('success', false, 'error', 'password_too_short');
  END IF;

  SELECT * INTO v_inv
  FROM invitations
  WHERE token = p_token
    AND used_at IS NULL
    AND expires_at > now()
    AND intended_role = 'retail'
  LIMIT 1
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'invalid_or_expired');
  END IF;

  IF EXISTS (SELECT 1 FROM accounts WHERE login_id = p_login_id) THEN
    RETURN json_build_object('success', false, 'error', 'login_id_exists');
  END IF;

  SELECT company_name INTO v_name FROM customers WHERE id = v_inv.customer_id;

  INSERT INTO accounts (
    login_id, name, role, password, password_hash, tenant_id, customer_id,
    consented_terms_version, consented_privacy_version, consented_at
  )
  VALUES (
    p_login_id, v_name, 'retail', '', crypt(p_password, gen_salt('bf', 10)),
    v_inv.tenant_id, v_inv.customer_id,
    p_terms_version, p_privacy_version, now()
  );

  INSERT INTO retail_memberships (login_id, tenant_id, customer_id)
  VALUES (p_login_id, v_inv.tenant_id, v_inv.customer_id)
  ON CONFLICT (login_id, tenant_id) DO NOTHING;

  UPDATE invitations SET used_at = now() WHERE id = v_inv.id;

  RETURN json_build_object('success', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.register_retail_account(text, text, text, text, text) TO anon, authenticated;
