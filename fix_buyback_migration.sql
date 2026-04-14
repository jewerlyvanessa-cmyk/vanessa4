-- Simple migration to fix buyback functionality
-- Run this to create the required database structure

-- Drop and recreate order_items table with correct structure
DROP TABLE IF EXISTS order_items CASCADE;

CREATE TABLE order_items (
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

-- Add order_number column if not exists
ALTER TABLE orders ADD COLUMN IF NOT EXISTS order_number TEXT UNIQUE;

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_order_items_order_id ON order_items(order_id);
CREATE INDEX IF NOT EXISTS idx_orders_order_number ON orders(order_number);

-- Insert test data for order BGEJ19304861
-- First, ensure the order exists
INSERT INTO orders (order_type, status, customer_id, branch_id, order_number, created_at)
SELECT 'jual', 'completed', c.customer_id, 1, 'BGEJ19304861', now()
FROM customers c
WHERE c.name = 'Test Customer'
LIMIT 1;

-- Insert test item for the order
INSERT INTO order_items (
    order_id, nama_item, kode_produk, weight, qty, harga_per_gram,
    material, purity, kategori, jenis, tipe, subtotal, total
)
SELECT
    o.order_id,
    'Cincin Emas',
    'PRD-001',
    5.5,
    1,
    1000000,
    'Emas',
    '24K',
    'PERHIASAN',
    'CINCIN',
    'BIASA',
    (5.5 * 1000000),
    (5.5 * 1000000)
FROM orders o
WHERE o.order_number = 'BGEJ19304861'
LIMIT 1;
