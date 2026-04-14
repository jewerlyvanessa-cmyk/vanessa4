-- Migration: Update database schema to match tabel2.txt (Simplified)
-- Date: 2026-01-15
-- Description: Update tables to match the new schema from tabel2.txt

-- Step 0: Drop dependent views and triggers
DROP VIEW IF EXISTS orders_view;
DROP TRIGGER IF EXISTS trg_prevent_nota_update ON orders;
DROP FUNCTION IF EXISTS prevent_nota_order_update();

-- Step 1: Update items table structure
ALTER TABLE items ADD COLUMN IF NOT EXISTS kode_produk TEXT;
UPDATE items SET kode_produk = 'ITEM-' || item_id::TEXT WHERE kode_produk IS NULL AND item_id IS NOT NULL;
ALTER TABLE items ALTER COLUMN kode_produk SET NOT NULL;
ALTER TABLE items ALTER COLUMN branch_id SET NOT NULL;

-- Drop old columns from items
ALTER TABLE items DROP COLUMN IF EXISTS item_code CASCADE;
ALTER TABLE items DROP COLUMN IF EXISTS item_code_source CASCADE;
ALTER TABLE items DROP COLUMN IF EXISTS qr_code CASCADE;
ALTER TABLE items DROP COLUMN IF EXISTS ownership CASCADE;
ALTER TABLE items DROP COLUMN IF EXISTS stock_type CASCADE;
ALTER TABLE items DROP COLUMN IF EXISTS is_quick_registered CASCADE;
ALTER TABLE items DROP COLUMN IF EXISTS is_estimated CASCADE;
ALTER TABLE items DROP COLUMN IF EXISTS quantity CASCADE;
ALTER TABLE items DROP COLUMN IF EXISTS photo_url CASCADE;

-- Step 2: Update orders table structure
-- Drop old columns
ALTER TABLE orders DROP COLUMN IF EXISTS jumlah CASCADE;
ALTER TABLE orders DROP COLUMN IF EXISTS total_akhir CASCADE;
ALTER TABLE orders DROP COLUMN IF EXISTS harga_per_gram CASCADE;
ALTER TABLE orders DROP COLUMN IF EXISTS status CASCADE;
ALTER TABLE orders DROP COLUMN IF EXISTS terbilang CASCADE;
ALTER TABLE orders DROP COLUMN IF EXISTS qty CASCADE;
ALTER TABLE orders DROP COLUMN IF EXISTS foto_new CASCADE;
ALTER TABLE orders DROP COLUMN IF EXISTS item_id CASCADE;
ALTER TABLE orders DROP COLUMN IF EXISTS nota_order CASCADE;

-- Add new columns
ALTER TABLE orders ADD COLUMN IF NOT EXISTS order_number TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS diskon DECIMAL(5,2) DEFAULT 0;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS total NUMERIC(15,2) DEFAULT 0;

-- Set default user_id for existing records
UPDATE orders SET user_id = 6 WHERE user_id IS NULL;
ALTER TABLE orders ALTER COLUMN user_id SET NOT NULL;

-- Step 3: Update order_items table structure
-- Rename berat to weight to match tabel2.txt
ALTER TABLE order_items RENAME COLUMN berat TO weight;

-- Set default values for existing records
UPDATE order_items SET weight = 0 WHERE weight IS NULL;
UPDATE order_items SET harga_per_gram = 0 WHERE harga_per_gram IS NULL;

-- Add new columns to order_items
ALTER TABLE order_items ADD COLUMN IF NOT EXISTS qty INTEGER DEFAULT 1;
ALTER TABLE order_items ADD COLUMN IF NOT EXISTS photo_produk TEXT;

-- Drop old columns from order_items
ALTER TABLE order_items DROP COLUMN IF EXISTS diskon CASCADE;
ALTER TABLE order_items DROP COLUMN IF EXISTS total CASCADE;
ALTER TABLE order_items DROP COLUMN IF EXISTS total_akhir CASCADE;
ALTER TABLE order_items DROP COLUMN IF EXISTS terbilang CASCADE;

-- Step 4: Update payments table structure
ALTER TABLE payments DROP COLUMN IF EXISTS timestamp CASCADE;
ALTER TABLE payments ALTER COLUMN order_id SET NOT NULL;

-- Step 5: Update customers table
ALTER TABLE customers DROP COLUMN IF EXISTS email CASCADE;

-- Step 6: Create indexes as per tabel2.txt
CREATE INDEX IF NOT EXISTS idx_branches_name ON branches(name);
CREATE INDEX IF NOT EXISTS idx_branches_initials ON branches(initials);
CREATE INDEX IF NOT EXISTS idx_users_status ON users(status);
CREATE INDEX IF NOT EXISTS idx_user_branch_roles_user_id ON user_branch_roles(user_id);
CREATE INDEX IF NOT EXISTS idx_user_branch_roles_branch_id ON user_branch_roles(branch_id);
CREATE INDEX IF NOT EXISTS idx_user_branch_roles_role ON user_branch_roles(role);
CREATE INDEX IF NOT EXISTS idx_items_branch_id ON items(branch_id);
CREATE INDEX IF NOT EXISTS idx_items_status ON items(status);
CREATE INDEX IF NOT EXISTS idx_items_kategori ON items(kategori);
CREATE INDEX IF NOT EXISTS idx_customers_phone ON customers(phone);
CREATE INDEX IF NOT EXISTS idx_customers_name ON customers(name);
CREATE INDEX IF NOT EXISTS idx_orders_branch_id ON orders(branch_id);
CREATE INDEX IF NOT EXISTS idx_orders_user_id ON orders(user_id);
CREATE INDEX IF NOT EXISTS idx_orders_customer_id ON orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_orders_order_number ON orders(order_number);
CREATE INDEX IF NOT EXISTS idx_order_items_order_id ON order_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_items_item_id ON order_items(item_id);
CREATE INDEX IF NOT EXISTS idx_payments_payment_date ON payments(payment_date);

COMMIT;
