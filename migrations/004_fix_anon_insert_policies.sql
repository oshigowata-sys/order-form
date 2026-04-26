-- orders_anon_insert / order_items_anon_insert の再作成
-- fix_anon_rls_all_tables 適用時に DROP されたまま再作成されなかった可能性があるため

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'orders' AND policyname = 'orders_anon_insert'
  ) THEN
    EXECUTE 'CREATE POLICY "orders_anon_insert" ON orders FOR INSERT TO anon WITH CHECK (true)';
    RAISE NOTICE 'orders_anon_insert を作成しました';
  ELSE
    RAISE NOTICE 'orders_anon_insert はすでに存在します';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'order_items' AND policyname = 'order_items_anon_insert'
  ) THEN
    EXECUTE 'CREATE POLICY "order_items_anon_insert" ON order_items FOR INSERT TO anon WITH CHECK (true)';
    RAISE NOTICE 'order_items_anon_insert を作成しました';
  ELSE
    RAISE NOTICE 'order_items_anon_insert はすでに存在します';
  END IF;
END $$;
