-- Migration: Create item_conditions table for buyback orders
-- Date: 2026-02-06
-- Description: Create table to store item condition data for buyback orders

-- Create item_conditions table
CREATE TABLE IF NOT EXISTS item_conditions (
    condition_id BIGSERIAL PRIMARY KEY,
    item_id BIGINT NOT NULL REFERENCES items(item_id),
    order_id BIGINT NOT NULL REFERENCES orders(order_id),
    kondisi_fisik VARCHAR(50) DEFAULT 'BAIK',
    kerusakan TEXT[], -- Array of damage descriptions
    berat_awal NUMERIC(10,2), -- Original weight before any adjustments
    berat_akhir NUMERIC(10,2), -- Final weight after adjustments
    penyesuaian_berat NUMERIC(10,2) DEFAULT 0, -- Weight adjustment amount
    keaslian VARCHAR(50), -- Authenticity status
    sertifikat VARCHAR(100), -- Certificate information
    harga_per_gram NUMERIC(15,2), -- Price per gram for buyback
    potongan_kondisi NUMERIC(15,2) DEFAULT 0, -- Condition deduction
    nilai_resale NUMERIC(15,2), -- Resale value
    harga_beli NUMERIC(15,2), -- Final buyback price
    untung_rugi VARCHAR(20), -- Profit/Loss status
    catatan_kondisi TEXT, -- Condition notes
    foto_kondisi TEXT[], -- Array of condition photo URLs
    dinilai_oleh BIGINT REFERENCES users(user_id), -- User who evaluated
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(item_id, order_id) -- One condition record per item per order
);

-- Create indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_item_conditions_item_id ON item_conditions(item_id);
CREATE INDEX IF NOT EXISTS idx_item_conditions_order_id ON item_conditions(order_id);
CREATE INDEX IF NOT EXISTS idx_item_conditions_dinilai_oleh ON item_conditions(dinilai_oleh);

-- Add comment to table
COMMENT ON TABLE item_conditions IS 'Stores detailed condition information for items in buyback orders';

COMMIT;
