-- Migration to synchronize database for buyback functionality
-- This adds order_number column and order_items table to support buyback lookups

-- Add order_number column to orders table
ALTER TABLE orders ADD COLUMN IF NOT EXISTS order_number TEXT UNIQUE;

-- Create order_items table
CREATE TABLE IF NOT EXISTS order_items (
    order_item_id BIGSERIAL PRIMARY KEY,
    order_id BIGINT REFERENCES orders(order_id) ON DELETE CASCADE,
    item_id BIGINT REFERENCES items(item_id),
    nama_item TEXT,
    kode_produk TEXT,
    weight NUMERIC(10,2),
    qty INTEGER DEFAULT 1,
    harga_per_gram NUMERIC(10,2),
    material TEXT,
    purity TEXT,
    kategori TEXT,
    jenis TEXT,
    tipe TEXT,
    subtotal NUMERIC(10,2),
    total NUMERIC(10,2),
    diskon NUMERIC(10,2) DEFAULT 0,
    kondisi_barang JSONB,
    created_at TIMESTAMP DEFAULT now(),
    updated_at TIMESTAMP DEFAULT now()
);

-- Create index for performance
CREATE INDEX IF NOT EXISTS idx_order_items_order_id ON order_items(order_id);
CREATE INDEX IF NOT EXISTS idx_orders_order_number ON orders(order_number);

-- Migrate existing data from orders to order_items
-- Only for orders that have item data directly in orders table
INSERT INTO order_items (
    order_id, item_id, nama_item, kode_produk, weight, qty, harga_per_gram,
    material, purity, kategori, jenis, tipe, subtotal, total, diskon
)
SELECT
    o.order_id,
    o.item_id,
    COALESCE(o.name, i.name),
    COALESCE(o.scanned_qr, i.qr_code),
    COALESCE(o.weight, i.weight),
    COALESCE(o.quantity, 1),
    o.harga_per_gram,
    COALESCE(o.material, i.material),
    COALESCE(o.purity, i.purity),
    i.kategori,
    i.jenis,
    i.tipe,
    (COALESCE(o.weight, i.weight, 0) * COALESCE(o.harga_per_gram, 0)) as subtotal,
    (COALESCE(o.weight, i.weight, 0) * COALESCE(o.harga_per_gram, 0)) as total,
    0 as diskon
FROM orders o
LEFT JOIN items i ON o.item_id = i.item_id
WHERE o.order_id NOT IN (SELECT DISTINCT order_id FROM order_items)
AND (o.name IS NOT NULL OR o.weight IS NOT NULL OR o.item_id IS NOT NULL);

-- Update existing orders to have order_number (if nota_order exists, copy it)
UPDATE orders SET order_number = nota_order WHERE order_number IS NULL AND nota_order IS NOT NULL;

-- For orders without nota_order or order_number, generate order_number based on order_id
UPDATE orders SET order_number = 'ORDER-' || order_id::TEXT WHERE order_number IS NULL;
