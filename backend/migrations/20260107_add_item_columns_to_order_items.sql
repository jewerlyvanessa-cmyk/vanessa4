-- Migration: Add kategori, jenis, and tipe columns to order_items table
ALTER TABLE order_items ADD COLUMN kategori VARCHAR(50);
ALTER TABLE order_items ADD COLUMN jenis VARCHAR(100);
ALTER TABLE order_items ADD COLUMN tipe VARCHAR(50);
