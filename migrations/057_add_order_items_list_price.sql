-- 057: order_items に上代（list_price）を追加
-- 納品書ごとに上代を編集できるようにするため、明細行にスナップショットとして保存する。
-- （見積書 quotation_items.list_price と同じ方式。021参照）
-- add-only：既存カラム・関数には一切触れない。既存行は NULL＝従来通り商品マスタの値を表示。
--
-- 2026-07-07 実行（Supabase apply_migration: add_order_items_list_price）。
-- 画面側の対応：父親版 PR #34（共通版への展開は別途）。

ALTER TABLE order_items
  ADD COLUMN IF NOT EXISTS list_price integer;

COMMENT ON COLUMN order_items.list_price IS '上代（納品書ごとの編集値。NULL=商品マスタの現在値を表示）';
