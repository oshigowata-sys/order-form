-- 058: orders に通知既読日時（seen_at）を追加
-- 通知ベルの「見たら未読数が減る」用。NULL＝未読。
-- 注文詳細を開いた時（orders.html openDetail → markOrderSeen）に現在時刻を入れる。
-- add-only：既存カラム・関数には一切触れない。
--
-- 2026-07-07 実行（Supabase apply_migration: add_orders_seen_at）。
-- 画面側の対応：共通版 PR（notification-bell.js の未読数バッジ・パネル色分け）。

ALTER TABLE orders
  ADD COLUMN IF NOT EXISTS seen_at timestamptz;

COMMENT ON COLUMN orders.seen_at IS '通知既読日時（NULL=未読。注文詳細を開いた時に記録・通知ベルの未読数と色分けに使用）';
