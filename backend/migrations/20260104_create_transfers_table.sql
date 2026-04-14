-- Migration: Create transfers table for admin_toko
-- Date: 2026-01-04
-- Description: Create transfers table for goods transfer functionality

-- Tabel transfers untuk menyimpan data transfer barang antar cabang
CREATE TABLE IF NOT EXISTS transfers (
    transfer_id BIGSERIAL PRIMARY KEY,
    from_branch_id BIGINT REFERENCES branches(branch_id),
    to_branch_id BIGINT REFERENCES branches(branch_id),
    item_name TEXT NOT NULL,
    quantity INTEGER NOT NULL,
    notes TEXT,
    order_id BIGINT REFERENCES orders(order_id),
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'completed', 'rejected')),
    created_by BIGINT REFERENCES users(user_id),
    approved_by BIGINT REFERENCES users(user_id),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Index untuk performa query
CREATE INDEX IF NOT EXISTS idx_transfers_from_branch ON transfers(from_branch_id);
CREATE INDEX IF NOT EXISTS idx_transfers_to_branch ON transfers(to_branch_id);
CREATE INDEX IF NOT EXISTS idx_transfers_status ON transfers(status);
CREATE INDEX IF NOT EXISTS idx_transfers_created_at ON transfers(created_at);
