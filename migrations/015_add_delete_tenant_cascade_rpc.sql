-- Migration: add super-admin RPC to delete a tenant and its related data
-- Apply in Supabase Dashboard > SQL Editor.

CREATE OR REPLACE FUNCTION public.delete_tenant_cascade(
  p_tenant_id uuid
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_tenant_name text;
  v_account_emails text[];
  v_deleted_users integer := 0;
BEGIN
  IF jwt_role() != 'super_admin' THEN
    RETURN json_build_object('success', false, 'error', 'forbidden');
  END IF;

  SELECT name INTO v_tenant_name
  FROM tenants
  WHERE id = p_tenant_id;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'not_found');
  END IF;

  SELECT COALESCE(array_agg(
    CASE
      WHEN login_id LIKE '%@%' THEN login_id
      ELSE login_id || '@meguree.internal'
    END
  ), ARRAY[]::text[])
  INTO v_account_emails
  FROM accounts
  WHERE tenant_id = p_tenant_id;

  DELETE FROM order_items
  WHERE order_id IN (
    SELECT id FROM orders WHERE tenant_id = p_tenant_id
  );

  DELETE FROM invoices WHERE tenant_id = p_tenant_id;
  DELETE FROM orders WHERE tenant_id = p_tenant_id;
  DELETE FROM pricing WHERE tenant_id = p_tenant_id;
  DELETE FROM products WHERE tenant_id = p_tenant_id;
  DELETE FROM customers WHERE tenant_id = p_tenant_id;
  DELETE FROM invitations WHERE tenant_id = p_tenant_id;
  DELETE FROM settings WHERE tenant_id = p_tenant_id;

  IF to_regclass('public.tenant_bank_accounts') IS NOT NULL THEN
    EXECUTE 'DELETE FROM public.tenant_bank_accounts WHERE tenant_id = $1' USING p_tenant_id;
  END IF;

  IF to_regclass('public.audit_log') IS NOT NULL
     AND EXISTS (
       SELECT 1
       FROM information_schema.columns
       WHERE table_schema = 'public'
         AND table_name = 'audit_log'
         AND column_name = 'tenant_id'
     ) THEN
    EXECUTE 'DELETE FROM public.audit_log WHERE tenant_id = $1' USING p_tenant_id;
  END IF;

  DELETE FROM accounts WHERE tenant_id = p_tenant_id;

  IF COALESCE(array_length(v_account_emails, 1), 0) > 0 THEN
    DELETE FROM auth.identities
    WHERE user_id IN (
      SELECT id FROM auth.users WHERE email = ANY(v_account_emails)
    );

    DELETE FROM auth.users
    WHERE email = ANY(v_account_emails);

    GET DIAGNOSTICS v_deleted_users = ROW_COUNT;
  END IF;

  DELETE FROM tenants WHERE id = p_tenant_id;

  RETURN json_build_object(
    'success', true,
    'tenant_id', p_tenant_id,
    'tenant_name', v_tenant_name,
    'deleted_auth_users', v_deleted_users
  );
EXCEPTION
  WHEN OTHERS THEN
    RETURN json_build_object('success', false, 'error', 'db_error', 'detail', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION public.delete_tenant_cascade(uuid) TO authenticated, service_role;
