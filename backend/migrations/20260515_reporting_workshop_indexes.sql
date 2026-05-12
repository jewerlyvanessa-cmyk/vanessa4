-- Indeks lanjutan: laporan manajer (order completed hari ini) + query workshop
-- (cabang + order service/custom + filter created_at).
-- Jalankan setelah 20260514_orders_daily_performance_indexes.sql bila belum.

-- GET /reports/orders-completed-today — WHERE status + tanggal kalender + ORDER BY created_at
CREATE INDEX IF NOT EXISTS idx_orders_status_created_at_desc
  ON orders (status, created_at DESC);

-- GET /api/workshop/dashboard, GET /api/workshop/reports — branch_id + service/custom + created_at
CREATE INDEX IF NOT EXISTS idx_orders_branch_service_custom_created_at
  ON orders (branch_id, created_at DESC)
  WHERE order_type IN ('service', 'custom');

COMMENT ON INDEX idx_orders_status_created_at_desc IS
  'Laporan: order completed + urutan created_at (manajer / orders-completed-today).';
COMMENT ON INDEX idx_orders_branch_service_custom_created_at IS
  'Workshop: cabang + tipe service|custom + rentang tanggal (dashboard & reports).';
