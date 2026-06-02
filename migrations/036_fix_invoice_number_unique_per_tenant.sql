-- Migration 036: 請求書番号の重複NG制約をテナント単位に変更
-- Purpose:
--   現状の `invoices_invoice_number_key` は全テナント共通の UNIQUE 制約のため、
--   別テナントが同じ請求書番号（例: INV-202606-001）を先に発行していると、
--   自テナントから同番号で INSERT すると HTTP 409 (duplicate key) で失敗する。
--
--   採番ロジック（invoice-list.html:661）は自テナント内の件数+1で番号を生成する
--   ため、本来は会社（テナント）ごとに独立して採番されるべき。
--
--   そのため、UNIQUE 制約を (tenant_id, invoice_number) の複合キーに張り替える。
--
-- 影響:
--   - 既存データ：同じ invoice_number が複数テナントに存在する状態を許容する
--   - フロントエンドのコード変更：不要（採番・検索とも tenant_id を含めるか
--     RLS で自テナント限定されている）
--   - 既存の RLS ポリシー `invoices_tenant_all` (tenant_id = jwt_tenant_id())
--     によって、別テナントの同番号レコードは PATCH/SELECT で一切見えない
--
-- ロールバック:
--   ALTER TABLE invoices
--     DROP CONSTRAINT invoices_tenant_invoice_number_key,
--     ADD CONSTRAINT invoices_invoice_number_key UNIQUE (invoice_number);
--   ※ ただし全テナントで invoice_number が一意である前提が必要

ALTER TABLE invoices
  DROP CONSTRAINT IF EXISTS invoices_invoice_number_key;

ALTER TABLE invoices
  ADD CONSTRAINT invoices_tenant_invoice_number_key UNIQUE (tenant_id, invoice_number);
