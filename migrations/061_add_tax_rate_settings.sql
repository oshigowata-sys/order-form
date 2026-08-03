-- 061: settings に「消費税率の変更予定」を追加
-- 消費税率が改定されたとき、コードを直さず設定画面から切り替えられるようにする。
-- 切替日方式：受注日がその日以降なら新税率、それより前は当時の税率のまま（インボイス制度・帳簿保存に整合）。
-- add-only：既存カラム・関数には一切触れない。
--
-- 形式（配列・何段階でも登録可・空配列＝現行のまま）：
--   [{"from":"2027-04-01","standard":12,"reduced":10}]
--   from     … 適用開始日（この日の受注から新税率）
--   standard … 標準税率（%）
--   reduced  … 軽減税率（%・食品）
-- 配列が空、または受注日が最古の from より前のときは既定 標準10% / 軽減8%（画面側 tax-rates.js の DEFAULT）。

ALTER TABLE public.settings
  ADD COLUMN IF NOT EXISTS tax_rate_changes jsonb DEFAULT '[]'::jsonb;

COMMENT ON COLUMN public.settings.tax_rate_changes IS '消費税率の変更予定（適用開始日つき・[{from,standard,reduced}]・空＝標準10%/軽減8%）';

-- ============================================================
-- DB側でも同じ判定ができるようにする（小売店向けRPCが税込合計を出すため）
-- ============================================================

-- その日・その区分（軽減/標準）の税率を掛け算用の小数で返す（例：0.10）。
-- 設定が無ければ既定の 標準10% / 軽減8%。画面側 tax-rates.js と同じ判定。
CREATE OR REPLACE FUNCTION public.tax_rate_for(p_tenant_id uuid, p_date date, p_is_food boolean)
RETURNS numeric
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT CASE WHEN p_is_food THEN (c->>'reduced')::numeric ELSE (c->>'standard')::numeric END
       FROM settings s,
            LATERAL jsonb_array_elements(COALESCE(s.tax_rate_changes, '[]'::jsonb)) c
      WHERE s.tenant_id = p_tenant_id
        AND (c->>'from') IS NOT NULL
        AND (c->>'from')::date <= COALESCE(p_date, CURRENT_DATE)
      ORDER BY (c->>'from')::date DESC
      LIMIT 1),
    CASE WHEN p_is_food THEN 8 ELSE 10 END
  ) / 100;
$$;

GRANT EXECUTE ON FUNCTION public.tax_rate_for(uuid, date, boolean) TO authenticated;

-- 小売店の注文画面（shop.html）が、取引している卸業者の税率設定だけを読むためのRPC。
-- 返すのは税率の配列のみ（会社名・住所などの設定は返さない）。
CREATE OR REPLACE FUNCTION public.get_my_tax_rates(p_tenant_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(s.tax_rate_changes, '[]'::jsonb)
  FROM settings s
  WHERE s.tenant_id = (SELECT b.tenant_id FROM retail_my_binding(p_tenant_id) b LIMIT 1);
$$;

GRANT EXECUTE ON FUNCTION public.get_my_tax_rates(uuid) TO authenticated;

-- 小売店の注文履歴の税込合計も設定の税率で計算する。
-- 引数・戻り値の形はそのまま（add-only 準拠）。中の税率だけ tax_rate_for に置き換え。
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
                             tax_rate_for(me.tenant_id, o.order_date, p.is_food)))
              FROM order_items oi JOIN products p ON p.id = oi.product_id
              WHERE oi.order_id = o.id), 0)::bigint
  FROM orders o, me
  WHERE o.tenant_id = me.tenant_id
    AND o.customer_id = me.customer_id
  ORDER BY o.order_date DESC, o.created_at DESC;
$$;

GRANT EXECUTE ON FUNCTION public.get_my_orders(uuid) TO authenticated;
