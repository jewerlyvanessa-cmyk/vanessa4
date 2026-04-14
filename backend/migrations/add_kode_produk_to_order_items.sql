-- Migration to add kode_produk column to order_items table
ALTER TABLE order_items ADD COLUMN IF NOT EXISTS kode_produk VARCHAR(100);
