-- Migration: Tighten get_customer_name_by_id with tenant_id filter
-- Apply in Supabase Dashboard > SQL Editor.
--
-- PR #199 で products / pricing / create_anon_order のテナント分離は実装済みだが、
-- 取引先名取得の RPC（get_customer_name_by_id）は customer_id だけで呼ばれていたため、
-- 別テナントの customer_id でも社名が取得できる脆弱性が残っていた。
--
-- 対応：tenant_id と customer_id の両方が一致した場合のみ company_name を返す。

DROP FUNCTION IF EXISTS public.get_customer_name_by_id(uuid);

CREATE OR REPLACE FUNCTION public.get_customer_name_by_id(p_tenant_id uuid, p_customer_id uuid)
RETURNS text
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $function$
  SELECT company_name FROM customers
  WHERE id = p_customer_id
    AND tenant_id = p_tenant_id
  LIMIT 1;
$function$;

GRANT EXECUTE ON FUNCTION public.get_customer_name_by_id(uuid, uuid) TO anon, authenticated;
