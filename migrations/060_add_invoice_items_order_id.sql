-- 060: invoice_items に order_id（どの受注の行か）を追加
--
-- 背景（バグ）：請求明細書は「受注（伝票）ごとのブロック」で印刷するが、発行時に凍結した
-- 明細（invoice_items）には "どの受注の行か" を持っていなかった。印刷時は受注を取り直して
-- 組み直し、凍結明細を **並び順（display_order）の位置だけ** で当て込んでいた。
-- 発行時と印刷時のどちらの取得も `order=order_date.asc` のみ＝同じ受注日が複数あると
-- 並びが保証されず、両者の順番がズレて「別の受注の内容が混ざる」事象が発生していた。
-- （demo テナントで再現：発行済み15件中9件でズレ・77行中44行が別位置）
--
-- add-only：既存カラム・関数には一切触れない。既存行は NULL のまま
--（画面側は NULL のとき従来ロジックへフォールバックする）。
--
-- 2026-08-01 実行（Supabase apply_migration: add_invoice_items_order_id）。

ALTER TABLE invoice_items
  ADD COLUMN IF NOT EXISTS order_id uuid;

COMMENT ON COLUMN invoice_items.order_id IS 'この明細行がどの受注（伝票）の行か。請求明細書の伝票ごとの区切りに使用。NULL=旧データ（画面側は並び順で復元）';
