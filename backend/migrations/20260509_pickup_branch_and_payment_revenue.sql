-- Cabang pengambilan untuk service/custom + atribusi pendapatan per pembayaran.
-- DP → revenue_branch_id = cabang order; pelunasan → revenue_branch_id = pickup (fallback order).

BEGIN;

ALTER TABLE orders
  ADD COLUMN IF NOT EXISTS pickup_branch_id BIGINT;

ALTER TABLE payments
  ADD COLUMN IF NOT EXISTS revenue_branch_id BIGINT;

CREATE INDEX IF NOT EXISTS idx_payments_revenue_branch_id
  ON payments (revenue_branch_id);

COMMENT ON COLUMN orders.pickup_branch_id IS
  'Cabang di mana customer mengambil; NULL = sama dengan branch_id order.';
COMMENT ON COLUMN payments.revenue_branch_id IS
  'Cabang untuk laporan pendapatan pembayaran ini; NULL = pakai orders.branch_id (legacy).';

COMMIT;
