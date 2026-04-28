-- Migration: Add rounded jumlah column to orders
-- Date: 2026-04-23
-- Description:
--   - Add `orders.jumlah` as a generated column derived from `orders.total`
--   - Rounding rule: round UP to nearest 5.000 (CEIL(total/5000)*5000)

-- Drop existing jumlah column (if any) to ensure consistent definition
ALTER TABLE orders DROP COLUMN IF EXISTS jumlah;

-- Add `jumlah` as generated rounded value from `total`
ALTER TABLE orders
ADD COLUMN jumlah NUMERIC GENERATED ALWAYS AS (
  CEIL((COALESCE(total, 0)) / 5000) * 5000
) STORED;

COMMIT;
