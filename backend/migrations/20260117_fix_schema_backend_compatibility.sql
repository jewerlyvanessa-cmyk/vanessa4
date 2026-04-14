-- Migration: Fix database schema to match backend implementation
-- Date: 2026-01-17
-- Description: Add missing columns and fix inconsistencies between database schema and backend code

-- Step 1: Add status column to orders table (required by backend)
ALTER TABLE orders ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'draft' CHECK (status IN ('draft','submitted','in_progress','done','cancelled'));

-- Step 2: Fix foreign key reference in orders table
-- Change branch_id to reference branches(branch_id) instead of user_branch_roles(branch_id)
-- First, we need to check if the current data is valid
-- If branch_id in orders references valid branch_id in branches, we can proceed

-- Step 3: Add missing columns to order_items table (used by backend)
ALTER TABLE order_items ADD COLUMN IF NOT EXISTS kode_produk VARCHAR(100);
ALTER TABLE order_items ADD COLUMN IF NOT EXISTS berat NUMERIC(10,2);
ALTER TABLE order_items ADD COLUMN IF NOT EXISTS subtotal NUMERIC(15,2) DEFAULT 0;
ALTER TABLE order_items ADD COLUMN IF NOT EXISTS diskon DECIMAL(5,2) DEFAULT 0;
ALTER TABLE order_items ADD COLUMN IF NOT EXISTS total NUMERIC(15,2) DEFAULT 0;

-- Step 4: Update existing order_items to calculate subtotal, diskon, and total
-- Assuming diskon is 0 for existing records
UPDATE order_items SET
  subtotal = COALESCE(jumlah, 0),
  diskon = 0,
  total = COALESCE(jumlah, 0)
WHERE subtotal IS NULL OR diskon IS NULL OR total IS NULL;

-- Step 5: Make subtotal, diskon, and total NOT NULL after populating data
ALTER TABLE order_items ALTER COLUMN subtotal SET NOT NULL;
ALTER TABLE order_items ALTER COLUMN diskon SET NOT NULL;
ALTER TABLE order_items ALTER COLUMN total SET NOT NULL;

-- Step 6: Add index for status column in orders
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status);

-- Step 7: Update any existing orders to have proper status
UPDATE orders SET status = 'draft' WHERE status IS NULL;

COMMIT;
