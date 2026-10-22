-- 062: customers に「よみ（カナ）」name_kana を追加
-- 取引先のプルダウン・一覧を「あいうえお順」に並べるため。
-- 会社名は漢字が混ざるため、そのままでは読みの順に並べられない（「北海道…」が「ほ」の位置に来ない）。
-- 読みの情報をどこにも持っていなかったので、取引先マスタに入力欄として足す。
--
-- 未入力（NULL）のときは画面側が「会社名から法人格（株式会社・有限会社・（株）など）を
-- 外した文字列」で並べる＝入力しなくても従来より良い並びになり、壊れない。
-- 並べ替えの実装：hikaru-order-form/customer-sort.js（MeguReeCustomerSort）
--
-- add-only：既存カラム・関数には一切触れない。既存行は NULL。
--
-- 2026-10-05 実行（Supabase apply_migration: add_customers_name_kana）。
-- 画面側の対応：父親版 PR #70（共通版への展開は別途）。

ALTER TABLE customers
  ADD COLUMN IF NOT EXISTS name_kana text;

COMMENT ON COLUMN customers.name_kana IS 'よみ（カナ）。取引先の並べ替え（あいうえお順）用。NULL=会社名から法人格を外した文字列で並べる';
