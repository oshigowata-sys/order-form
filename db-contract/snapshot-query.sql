-- MeguRee スキーマ現状スナップショット生成クエリ
-- 用途: 父親画面凍結の後方互換チェック。DB変更(migration)の前に Supabase で実行し、
--       返ってきた1つの文字列を db-contract/_current.psv に保存 → check-compat.py で基準と比較する。
-- 出力形式は schema-baseline.psv と同じ  kind|obj|member|sig
--   sig = column: md5(型+NOT NULL) / function: md5(引数->戻り値)  ※区切り文字に依存しない
-- 個人情報は一切読まない（information_schema / pg_catalog のみ）。

SELECT string_agg(line, E'\n' ORDER BY line) AS current_schema
FROM (
  SELECT 'column' || '|' || c.table_name || '|' || c.column_name || '|'
         || md5(c.data_type || c.is_nullable) AS line
  FROM information_schema.columns c
  JOIN information_schema.tables t
    ON t.table_schema = c.table_schema
   AND t.table_name  = c.table_name
   AND t.table_type  = 'BASE TABLE'
  WHERE c.table_schema = 'public'
  UNION ALL
  SELECT 'function' || '|' || p.proname || '|'
         || coalesce(pg_get_function_identity_arguments(p.oid), '') || '|'
         || md5(pg_get_function_identity_arguments(p.oid) || '->' || pg_get_function_result(p.oid)) AS line
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
) s;
