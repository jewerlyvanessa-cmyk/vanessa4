-- Indeks untuk hot path: order harian, pembayaran harian, daftar transfer.
-- Aman dijalankan berulang (IF NOT EXISTS). Jalankan setelah patch_vanessa3_production_complete.sql.

-- Pembayaran completed per tanggal aktivitas (orders/daily, /payments/daily*)
CREATE INDEX IF NOT EXISTS idx_payments_completed_payment_date
  ON payments (payment_date, order_id)
  WHERE status = 'completed';

CREATE INDEX IF NOT EXISTS idx_payments_completed_created_at
  ON payments (created_at, order_id)
  WHERE status = 'completed';

-- Atribusi pendapatan cabang pickup (cross-branch di orders/daily & payments)
CREATE INDEX IF NOT EXISTS idx_payments_completed_revenue_branch
  ON payments (revenue_branch_id, payment_date, order_id)
  WHERE status = 'completed' AND revenue_branch_id IS NOT NULL;

-- Transfer: filter cabang + status + urutan terbaru
CREATE INDEX IF NOT EXISTS idx_transfers_from_status_created
  ON transfers (from_branch_id, status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_transfers_to_status_created
  ON transfers (to_branch_id, status, created_at DESC);
