-- Migration: Create stock_mutations table for admin_toko
-- Date: 2026-01-04
-- Description: Create stock_mutations table for stock tracking functionality

-- Tabel stock_mutations untuk menyimpan data mutasi stok
CREATE TABLE IF NOT EXISTS stock_mutations (
    mutation_id BIGSERIAL PRIMARY KEY,
    item_id BIGINT REFERENCES items(item_id),
    branch_id BIGINT REFERENCES branches(branch_id),
    type TEXT NOT NULL CHECK (type IN ('in', 'out', 'transfer', 'adjustment')),
    quantity INTEGER NOT NULL,
    previous_stock INTEGER,
    current_stock INTEGER,
    notes TEXT,
    reference_id BIGINT, -- Could reference order_id, transfer_id, etc.
    reference_type TEXT, -- 'order', 'transfer', 'manual', etc.
    created_by BIGINT REFERENCES users(user_id),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Index untuk performa query
CREATE INDEX IF NOT EXISTS idx_stock_mutations_item_id ON stock_mutations(item_id);
CREATE INDEX IF NOT EXISTS idx_stock_mutations_branch_id ON stock_mutations(branch_id);
CREATE INDEX IF NOT EXISTS idx_stock_mutations_type ON stock_mutations(type);
CREATE INDEX IF NOT EXISTS idx_stock_mutations_created_at ON stock_mutations(created_at);
