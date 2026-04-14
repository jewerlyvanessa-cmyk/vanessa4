-- Migration: Update database schema to match tabel2.txt
-- Date: 2026-01-15
-- Description: Update tables to match the new schema from tabel2.txt

-- Step 0: Drop dependent views
DROP VIEW IF EXISTS orders_view;

-- Step 1: Update items table structure
ALTER TABLE items ADD COLUMN IF NOT EXISTS kode_produk TEXT;
UPDATE items SET kode_produk = 'ITEM-' || item_id::TEXT WHERE kode_produk IS NULL;
ALTER TABLE items ALTER COLUMN kode_produk SET NOT NULL;
ALTER TABLE items ALTER COLUMN branch_id SET NOT NULL;

-- Drop old columns
ALTER TABLE items DROP COLUMN IF EXISTS item_code;
ALTER TABLE items DROP COLUMN IF EXISTS item_code_source;
ALTER TABLE items DROP COLUMN IF EXISTS qr_code;
ALTER TABLE items DROP COLUMN IF EXISTS ownership;
ALTER TABLE items DROP COLUMN IF EXISTS stock_type;
ALTER TABLE items DROP COLUMN IF EXISTS is_quick_registered;
ALTER TABLE items DROP COLUMN IF EXISTS is_estimated;
ALTER TABLE items DROP COLUMN IF EXISTS quantity;
ALTER TABLE items DROP COLUMN IF EXISTS photo_url;

-- Step 2: Update orders table structure
ALTER TABLE orders DROP COLUMN IF EXISTS jumlah;
ALTER TABLE orders DROP COLUMN IF EXISTS total_akhir;
ALTER TABLE orders DROP COLUMN IF EXISTS harga_per_gram;
ALTER TABLE orders DROP COLUMN IF EXISTS status;
ALTER TABLE orders DROP COLUMN IF EXISTS terbilang;
ALTER TABLE orders DROP COLUMN IF EXISTS qty;
ALTER TABLE orders DROP COLUMN IF EXISTS foto_new;
ALTER TABLE orders DROP COLUMN IF EXISTS item_id;

-- Rename nota_order to order_number if exists
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'orders' AND column_name = 'nota_order') THEN
        ALTER TABLE orders RENAME COLUMN nota_order TO order_number;
    END IF;
END $$;

-- Add new columns
ALTER TABLE orders ADD COLUMN IF NOT EXISTS order_number TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS diskon DECIMAL(5,2) DEFAULT 0;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS total NUMERIC(15,2) DEFAULT 0;
ALTER TABLE orders ALTER COLUMN user_id SET NOT NULL;

-- Step 3: Update order_items table structure
-- Rename id to order_item_id if exists
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'order_items' AND column_name = 'id') THEN
        ALTER TABLE order_items ALTER COLUMN id TYPE BIGSERIAL;
        ALTER TABLE order_items RENAME COLUMN id TO order_item_id;
    END IF;
END $$;

-- Add new columns to order_items
ALTER TABLE order_items ADD COLUMN IF NOT EXISTS qty INTEGER DEFAULT 1;
ALTER TABLE order_items ADD COLUMN IF NOT EXISTS weight NUMERIC NOT NULL;
ALTER TABLE order_items ADD COLUMN IF NOT EXISTS harga_per_gram NUMERIC NOT NULL;
ALTER TABLE order_items ADD COLUMN IF NOT EXISTS photo_produk TEXT;

-- Drop old columns from order_items
ALTER TABLE order_items DROP COLUMN IF EXISTS diskon;
ALTER TABLE order_items DROP COLUMN IF EXISTS total;
ALTER TABLE order_items DROP COLUMN IF EXISTS total_akhir;
ALTER TABLE order_items DROP COLUMN IF EXISTS terbilang;

-- Step 4: Update payments table structure
ALTER TABLE payments DROP COLUMN IF EXISTS timestamp;
ALTER TABLE payments ALTER COLUMN order_id SET NOT NULL;

-- Step 5: Update customers table
ALTER TABLE customers DROP COLUMN IF EXISTS email;

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
