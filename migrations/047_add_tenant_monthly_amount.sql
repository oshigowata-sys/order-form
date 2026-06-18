-- Migration: 契約者ごとの月額実額（交渉価格）を保存するカラム追加
-- 背景: スーパー管理画面はプラン固定価格（starter/standard/premium/monitor）からしか
--       月売上を集計できず、24,800円のような交渉価格を表現できなかった。
--       実額が入っていればそれを優先し、無ければ従来のプラン価格で集計する。
-- 性質: 追加のみ（additive）・NULL許容・既存レコード/集計に影響なし（後方互換）
-- 適用方法: Supabase Dashboard > SQL Editor に貼り付けて実行（または MCP apply_migration）

ALTER TABLE tenants
  ADD COLUMN IF NOT EXISTS monthly_amount integer;

COMMENT ON COLUMN tenants.monthly_amount IS
  '月額の実際の契約金額（円・税抜）。交渉価格を入れる。NULL の場合はプラン固定価格で集計する。';
