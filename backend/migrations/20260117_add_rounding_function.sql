-- Migration: Update jumlah generated column with simplified rounding logic
-- Date: 2026-01-17
-- Description: Replace complex CASE expression with simple CEIL rounding

-- Drop existing jumlah column
ALTER TABLE order_items DROP COLUMN jumlah;

-- Add new jumlah column with simplified rounding: CEIL(amount / 5000) * 5000
ALTER TABLE order_items
ADD COLUMN jumlah NUMERIC GENERATED ALWAYS AS (
  CEIL((qty * weight * harga_per_gram * (1 - diskon / 100)) / 5000) * 5000
) STORED;

COMMIT;
