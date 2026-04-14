-- Migration: Remove unused nota_order column from orders table
-- Date: 2026-01-17
-- Description: Remove nota_order column as it's never used (always null), order_number is the active column

ALTER TABLE orders DROP COLUMN IF EXISTS nota_order CASCADE;

COMMIT;
