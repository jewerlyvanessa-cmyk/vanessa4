-- Migration: add quantity column to items table
-- Date: 2026-04-26
-- Notes:
-- - Existing schema uses `kode_produk` (legacy) and has no stock quantity column.
-- - This adds `quantity` with default 1 so stock pages can show and edit qty.

ALTER TABLE items ADD COLUMN IF NOT EXISTS quantity INTEGER DEFAULT 1;

UPDATE items SET quantity = 1 WHERE quantity IS NULL;

ALTER TABLE items ALTER COLUMN quantity SET NOT NULL;

