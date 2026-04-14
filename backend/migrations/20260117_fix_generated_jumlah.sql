-- Migration: Fix generated column jumlah in order_items table
-- Date: 2026-01-17
-- Description: Update jumlah generated column to include discount calculation (match frontend)

-- Drop the existing jumlah column if it exists (it should be a regular column now)
ALTER TABLE order_items DROP COLUMN IF EXISTS jumlah;

-- Add the jumlah column back as a generated column that includes discount
-- This matches the frontend calculation: qty * weight * harga_per_gram * (1 - diskon/100)
ALTER TABLE order_items
ADD COLUMN jumlah NUMERIC GENERATED ALWAYS AS (
  qty * weight * harga_per_gram * (1 - diskon / 100)
) STORED;

COMMIT;
