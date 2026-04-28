-- Migration: Backfill orders.total from order_items.total
-- Date: 2026-04-28
-- Description:
--   - Ensure legacy orders have correct `orders.total`
--   - `orders.jumlah` is generated from `orders.total` (rounded up to nearest 5.000)
--   - Formula:
--       base = SUM(order_items.total)
--       orders.total = base - (base * diskon%)

BEGIN;

-- Update orders.total using order_items.total as source-of-truth.
-- Only touch rows where total is zero (or NULL) to avoid unexpected changes.
WITH item_sums AS (
  SELECT
    oi.order_id,
    COALESCE(SUM(oi.total), 0) AS items_total
  FROM order_items oi
  GROUP BY oi.order_id
)
UPDATE orders o
SET total = (
  item_sums.items_total * (1 - (COALESCE(o.diskon, 0) / 100.0))
),
updated_at = NOW()
FROM item_sums
WHERE o.order_id = item_sums.order_id
  AND COALESCE(o.total, 0) = 0;

COMMIT;

