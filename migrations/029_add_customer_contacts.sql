-- Migration 029: add customer_contacts (multiple phones / faxes per customer)
-- Purpose:
--   customers.phone is a single text column. Wholesalers often need to record
--   multiple phone numbers (main / sales rep mobile) and one or more FAX
--   numbers per customer. This migration adds a separate customer_contacts
--   table WITHOUT touching customers.phone so existing display / PDF code
--   keeps working unchanged.
--
-- Design notes:
--   - customers.phone is kept as the "main phone" for backward compatibility.
--   - customer_contacts holds the full list (main phone + additional phones
--     + FAX numbers + free-text label).
--   - On save the frontend keeps customers.phone in sync with the first
--     phone-type entry in customer_contacts (display_order = 0).
--   - RLS follows the same pattern as customers (jwt_role() / jwt_tenant_id()).

CREATE TABLE IF NOT EXISTS public.customer_contacts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id UUID NOT NULL REFERENCES public.customers(id) ON DELETE CASCADE,
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  contact_type TEXT NOT NULL CHECK (contact_type IN ('phone', 'fax')),
  contact_value TEXT NOT NULL,
  label TEXT,
  display_order INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS customer_contacts_customer_id_idx
  ON public.customer_contacts (customer_id);
CREATE INDEX IF NOT EXISTS customer_contacts_tenant_id_idx
  ON public.customer_contacts (tenant_id);

ALTER TABLE public.customer_contacts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS customer_contacts_super_admin ON public.customer_contacts;
DROP POLICY IF EXISTS customer_contacts_tenant_all ON public.customer_contacts;

CREATE POLICY customer_contacts_super_admin ON public.customer_contacts
  AS PERMISSIVE FOR ALL TO public
  USING (jwt_role() = 'super_admin');

CREATE POLICY customer_contacts_tenant_all ON public.customer_contacts
  AS PERMISSIVE FOR ALL TO authenticated
  USING ((tenant_id)::text = jwt_tenant_id())
  WITH CHECK ((tenant_id)::text = jwt_tenant_id());

-- Backfill: copy existing customers.phone into customer_contacts as the
-- main phone entry. Skip customers that already have any contact row to
-- keep the migration idempotent.
INSERT INTO public.customer_contacts
  (customer_id, tenant_id, contact_type, contact_value, label, display_order)
SELECT c.id, c.tenant_id, 'phone', c.phone, '電話', 0
FROM public.customers c
WHERE c.phone IS NOT NULL
  AND c.phone <> ''
  AND NOT EXISTS (
    SELECT 1 FROM public.customer_contacts cc
    WHERE cc.customer_id = c.id
  );
