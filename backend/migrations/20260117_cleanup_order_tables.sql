-- Migration: Clean up order tables to match backend implementation
-- Date: 2026-01-17
-- Description: Remove unused columns from orders and order_items tables

-- Step 1: Remove item_id column from orders table (not used in current backend implementation)
-- This column was used in old single-item-per-order design
ALTER TABLE orders DROP COLUMN IF EXISTS item_id CASCADE;

-- Step 2: Remove berat column from order_items table (redundant with weight column)
-- The weight column is used for all calculations, berat is not consistently used
ALTER TABLE order_items DROP COLUMN IF EXISTS berat CASCADE;

-- Step 3: Ensure all required columns exist in order_items table
-- These should already be added by previous migration, but let's make sure
ALTER TABLE order_items ADD COLUMN IF NOT EXISTS kode_produk VARCHAR(100);
ALTER TABLE order_items ADD COLUMN IF NOT EXISTS subtotal NUMERIC(15,2) DEFAULT 0;
ALTER TABLE order_items ADD COLUMN IF NOT EXISTS diskon DECIMAL(5,2) DEFAULT 0;
ALTER TABLE order_items ADD COLUMN IF NOT EXISTS total NUMERIC(15,2) DEFAULT 0;

-- Step 4: Make sure NOT NULL constraints are applied where needed
ALTER TABLE order_items ALTER COLUMN subtotal SET NOT NULL;
ALTER TABLE order_items ALTER COLUMN diskon SET NOT NULL;
ALTER TABLE order_items ALTER COLUMN total SET NOT NULL;

COMMIT;
