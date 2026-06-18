-- Migration 049: 自社請求（MeguRee → 契約者）の発行・入金管理
--
-- 目的:
--   スーパー管理画面から、MeguReeが契約者(卸業者)に出す請求書を発行し、
--   入金状況(未入金/入金済/期日超過=催促)を管理できるようにする。
--   これはアプリ内の invoice.html（卸業者→小売店）とは別物の「自社請求」。
--
-- 性質: 追加のみ（後方互換）。新テーブルは最初から RLS 有効＋super_admin 限定。
--       採番＋控え保存は SECURITY DEFINER RPC で一括（番号重複・付け忘れ防止）。
-- 参照: 経理部/請求・入金運用ルール.md（MR-YYYY-NNN／税別→10%／前払い運用）

-- ================================================================
-- 1. 発行元・振込先（1行のみ・運営者が画面から登録）
-- ================================================================
CREATE TABLE IF NOT EXISTS public.meguree_billing_settings (
  id          integer PRIMARY KEY DEFAULT 1,
  issuer_name text NOT NULL DEFAULT 'MeguRee（めぐリー）',
  issuer_rep  text NOT NULL DEFAULT '',
  issuer_email text NOT NULL DEFAULT '',
  bank_name   text NOT NULL DEFAULT '',
  bank_branch text NOT NULL DEFAULT '',
  bank_type   text NOT NULL DEFAULT '普通',
  bank_number text NOT NULL DEFAULT '',
  bank_holder text NOT NULL DEFAULT '',
  updated_at  timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT meguree_billing_settings_singleton CHECK (id = 1)
);

INSERT INTO public.meguree_billing_settings (id) VALUES (1)
ON CONFLICT (id) DO NOTHING;

ALTER TABLE public.meguree_billing_settings ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.meguree_billing_settings FROM anon;

DROP POLICY IF EXISTS "meguree_billing_settings_super_admin" ON public.meguree_billing_settings;
CREATE POLICY "meguree_billing_settings_super_admin" ON public.meguree_billing_settings FOR ALL
  USING (jwt_role() = 'super_admin')
  WITH CHECK (jwt_role() = 'super_admin');

-- ================================================================
-- 2. 自社請求書の控え
--    発行元/振込先・宛名・明細は発行時点をスナップショット保存（後で変えても過去請求書は不変）
--    「催促中」は状態として持たず、status='unpaid' かつ due_date 超過を画面側で導出する。
-- ================================================================
CREATE TABLE IF NOT EXISTS public.meguree_invoices (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  invoice_number  text NOT NULL UNIQUE,                 -- MR-YYYY-NNN（会社全体・年内通番）
  tenant_id       uuid NULL REFERENCES public.tenants(id) ON DELETE SET NULL,
  bill_to_name    text NOT NULL,                        -- 宛名スナップショット
  target_period   text NOT NULL DEFAULT '',             -- 対象月ラベル（例「2026年7月分」）
  issued_date     date NOT NULL DEFAULT CURRENT_DATE,
  due_date        date NOT NULL,
  subtotal        integer NOT NULL DEFAULT 0,           -- 税別小計
  tax_amount      integer NOT NULL DEFAULT 0,           -- 消費税10%
  total           integer NOT NULL DEFAULT 0,           -- 税込合計
  items           jsonb NOT NULL DEFAULT '[]'::jsonb,   -- [{label, amount}] 明細スナップショット
  issuer_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,   -- 発行元・振込先スナップショット
  status          text NOT NULL DEFAULT 'unpaid',       -- 'unpaid' | 'paid'
  paid_date       date NULL,
  notes           text NULL,
  created_at      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT meguree_invoices_status_chk CHECK (status IN ('unpaid','paid'))
);

CREATE INDEX IF NOT EXISTS meguree_invoices_status_due_idx
  ON public.meguree_invoices (status, due_date);
CREATE INDEX IF NOT EXISTS meguree_invoices_issued_idx
  ON public.meguree_invoices (issued_date DESC);

ALTER TABLE public.meguree_invoices ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.meguree_invoices FROM anon;

DROP POLICY IF EXISTS "meguree_invoices_super_admin" ON public.meguree_invoices;
CREATE POLICY "meguree_invoices_super_admin" ON public.meguree_invoices FOR ALL
  USING (jwt_role() = 'super_admin')
  WITH CHECK (jwt_role() = 'super_admin');

-- ================================================================
-- 3. 発行RPC：super_admin 検証＋番号確定＋発行元スナップショット＋控え保存（一括）
--    入金更新・削除は RLS(super_admin) 下の直接 PATCH/DELETE で行う（既存の契約者操作と同方式）。
-- ================================================================
CREATE OR REPLACE FUNCTION public.create_meguree_invoice(
  p_tenant_id    uuid,
  p_bill_to_name text,
  p_target_period text,
  p_issued_date  date,
  p_due_date     date,
  p_subtotal     integer,
  p_tax_amount   integer,
  p_total        integer,
  p_items        jsonb,
  p_notes        text DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_year   text;
  v_seq    integer;
  v_number text;
  v_issuer jsonb;
  v_id     uuid;
BEGIN
  IF jwt_role() <> 'super_admin' THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  v_year := to_char(COALESCE(p_issued_date, CURRENT_DATE), 'YYYY');

  SELECT COALESCE(MAX(CAST(SUBSTRING(invoice_number FROM ('^MR-' || v_year || '-(\d+)$')) AS integer)), 0) + 1
    INTO v_seq
  FROM meguree_invoices
  WHERE invoice_number ~ ('^MR-' || v_year || '-\d+$');

  v_number := 'MR-' || v_year || '-' || lpad(v_seq::text, 3, '0');

  SELECT to_jsonb(s) INTO v_issuer
  FROM (
    SELECT issuer_name, issuer_rep, issuer_email,
           bank_name, bank_branch, bank_type, bank_number, bank_holder
    FROM meguree_billing_settings WHERE id = 1
  ) s;

  INSERT INTO meguree_invoices (
    invoice_number, tenant_id, bill_to_name, target_period, issued_date, due_date,
    subtotal, tax_amount, total, items, issuer_snapshot, status, notes
  ) VALUES (
    v_number, p_tenant_id, p_bill_to_name, COALESCE(p_target_period,''),
    COALESCE(p_issued_date, CURRENT_DATE), p_due_date,
    COALESCE(p_subtotal,0), COALESCE(p_tax_amount,0), COALESCE(p_total,0),
    COALESCE(p_items,'[]'::jsonb), COALESCE(v_issuer,'{}'::jsonb), 'unpaid', p_notes
  )
  RETURNING id INTO v_id;

  RETURN json_build_object('success', true, 'id', v_id, 'invoice_number', v_number);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.create_meguree_invoice(uuid,text,text,date,date,integer,integer,integer,jsonb,text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.create_meguree_invoice(uuid,text,text,date,date,integer,integer,integer,jsonb,text) TO authenticated;
