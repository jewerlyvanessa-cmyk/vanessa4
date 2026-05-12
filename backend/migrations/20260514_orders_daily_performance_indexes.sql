-- Indeks untuk GET /orders/daily & dashboard order-today: filter cabang + tanggal,
-- EXISTS pembayaran completed, dan join order_items.

CREATE INDEX IF NOT EXISTS idx_orders_branch_created_at
  ON orders (branch_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_orders_branch_user_created_at
  ON orders (branch_id, user_id, created_at DESC);

-- Mempercepat EXISTS (... payments ... completed ...) per order_id + filter tanggal
CREATE INDEX IF NOT EXISTS idx_payments_order_completed_created
  ON payments (order_id, created_at)
  WHERE status = 'completed';

COMMENT ON INDEX idx_orders_branch_created_at IS
  'Performa orders harian / cabang + urutan created_at.';
COMMENT ON INDEX idx_orders_branch_user_created_at IS
  'Performa filter CS: cabang + user_id + tanggal.';
COMMENT ON INDEX idx_payments_order_completed_created IS
  'Performa EXISTS pembayaran completed per order (orders/daily).';
